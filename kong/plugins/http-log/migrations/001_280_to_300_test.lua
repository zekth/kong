
local cjson = require "cjson"
local tablex = require "pl.tablex"

local helpers = require "spec/helpers"
local upgrade_helpers = require "spec/upgrade_helpers"

local HTTP_PORT = 29100

-- Copied from 3.x helpers.lua

local function http_server(port, opts)
  local threads = require "llthreads2.ex"
  opts = opts or {}
  local thread = threads.new({
    function(port, opts)
      local socket = require "socket"
      local server = assert(socket.tcp())
      server:settimeout(opts.timeout or 60)
      assert(server:setoption('reuseaddr', true))
      assert(server:bind("*", port))
      assert(server:listen())
      local client = assert(server:accept())

      local lines = {}
      local line, err
      repeat
        line, err = client:receive("*l")
        if err then
          break
        else
          table.insert(lines, line)
        end
      until line == ""

      if #lines > 0 and lines[1] == "GET /delay HTTP/1.0" then
        ngx.sleep(2)
      end

      if err then
        server:close()
        error(err)
      end

      local body, _ = client:receive("*a")

      client:send("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")
      client:close()
      server:close()

      return lines, body
    end
  }, port, opts)

  return thread:start()
end

describe("http-log plugin migration", function()

            local admin_client

            before_each(function()
                  admin_client = assert(helpers.admin_client())
            end)

            after_each(function()
                  if admin_client then
                     admin_client:close()
                  end
            end)

            lazy_setup(function ()
                  helpers.start_kong {
                        database = upgrade_helpers.database_type(),
                        nginx_conf = "spec/fixtures/custom_nginx.template"
                  }
            end)

            lazy_teardown(function ()
                  helpers.stop_kong()
            end)

            local log_server_url = "http://localhost:" .. HTTP_PORT .. "/"
            local upstream_server_url = "http://" .. helpers.mock_upstream_host .. ":" .. helpers.mock_upstream_port .. "/"

            local custom_header_name = "X-Test-Header"
            local custom_header_content = "this is it"

            it("can setup http-log proxy #old_before", function ()
                  local res = assert(admin_client:send {
                                        method = "POST",
                                        path = "/plugins/",
                                        body = {
                                           name = "http-log",
                                           config = {
                                              http_endpoint = log_server_url,
                                              headers = { [custom_header_name] = {custom_header_content} }
                                           }
                                        },
                                        headers = {
                                           ["Content-Type"] = "application/json"
                                        }
                  })
                  assert.res_status(201, res)
                  res = assert(admin_client:send {
                                  method = "POST",
                                  path = "/services/",
                                  body = {
                                     name = "example-service",
                                     url = upstream_server_url
                                  },
                                  headers = {
                                     ["Content-Type"] = "application/json"
                                  }
                  })
                  assert.res_status(201, res)
                  res = assert(admin_client:send {
                                  method = "POST",
                                  path = "/services/example-service/routes",
                                  body = {
                                     hosts = { "example.com" },
                                  },
                                  headers = {
                                     ["Content-Type"] = "application/json"
                                  }
                  })
                  assert.res_status(201, res)
            end)

            local function verify_log_header_is_added()
               local thread = http_server(HTTP_PORT, { timeout = 10 })
               local proxy_client = assert(helpers.proxy_client())
               local res = assert(proxy_client:send {
                                     method  = "GET",
                                     headers = {
                                        ["Host"] = "example.com",
                                     },
                                     path = "/",
               })
               assert.res_status(200, res)
               proxy_client:close()

               local ok, headers = thread:join()
               assert.truthy(ok)

               -- verify that the log HTTP request had the configured header
               local idx = tablex.find(headers, custom_header_name .. ": " .. custom_header_content)
               assert.not_nil(idx, headers)
            end

            it("can send request #old_after_up", function ()
                  verify_log_header_is_added()
            end)

            it("can send request #new_after_up", function ()
                  verify_log_header_is_added()
            end)

            it("has updated http-log configuration #new_after_finish", function ()
                  local res = assert(admin_client:send {
                                        method = "GET",
                                        path = "/plugins/"
                  })
                  local body = cjson.decode(assert.res_status(200, res))
                  assert.equal(1, #body.data)
                  assert.equal(custom_header_content, body.data[1].config.headers[custom_header_name])

                  verify_log_header_is_added()
            end)
end)
