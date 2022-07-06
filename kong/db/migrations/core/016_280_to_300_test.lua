local cjson = require "cjson"
local inspect = require "inspect"

local upgrade_helpers = require "spec/upgrade_helpers"

local HEADERS = { ["Content-Type"] = "application/json" }

describe("database migration #old_after", function()
            it("has created the expected new columns", function()
                  assert.table_has_column("targets", "cache_key", "text")
                  assert.table_has_column("upstreams", "hash_on_query_arg", "text")
                  assert.table_has_column("upstreams", "hash_fallback_query_arg", "text")
                  assert.table_has_column("upstreams", "hash_on_uri_capture", "text")
                  assert.table_has_column("upstreams", "hash_fallback_uri_capture", "text")
            end)
end)

describe("vault related data migration", function()

            local admin_client

            before_each(function()
                  admin_client = upgrade_helpers.admin_client()
            end)

            after_each(function()
                  if admin_client then
                     admin_client:close()
                  end
            end)

            describe("upgrade #old_before", function()
                        it("creates three beta vaults", function ()
                              for i = 1, 3 do
                                 local res = admin_client:put("/vaults-beta/env-" .. i, {
                                                                 headers = HEADERS,
                                                                 body = {
                                                                    name = "env",
                                                                 },
                                 })
                                 assert.res_status(200, res)
                              end
                        end)
            end)

            describe("upgrade #old_after_up", function()
                        -- nothing to test here as of now
            end)

            describe("upgrade #new_after_up", function()
                        -- nothing to test here as of now
            end)

            describe("upgrade #new_after_finish", function()
                        it("has three vaults properly migrated", function ()
                              local res = admin_client:get("/vaults")
                              local body = assert.res_status(200, res)
                              local json = cjson.decode(body)
                              assert.equal(3, #json.data)
                        end)
            end)
end)
