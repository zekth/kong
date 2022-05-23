local pdk_tracer = require "kong.pdk.tracing".new()
local utils = require "kong.tools.utils"
local tablepool = require "tablepool"
local tablex = require "pl.tablex"
local base = require "resty.core.base"
local cjson = require "cjson"
local ngx_re = require "ngx.re"

local ngx = ngx
local var = ngx.var
local pack = utils.pack
local unpack = utils.unpack
local insert = table.insert
local new_tab = base.new_tab
local time_ns = utils.time_ns
local tablepool_release = tablepool.release
local get_method = ngx.req.get_method
local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local concat = table.concat
local cjson_encode = cjson.encode
local _log_prefix = "[tracing] "
local split = ngx_re.split

local _M = {}
local tracer = pdk_tracer
local NOOP = function() end
local available_types = {}

local POOL_SPAN_STORAGE = "KONG_SPAN_STORAGE"

-- db query
function _M.db_query(connector)
  local f = connector.query

  local function wrap(self, sql, ...)
    local span = tracer.start_span("query")
    span:set_attribute("db.system", kong.db and kong.db.strategy)
    span:set_attribute("db.statement", sql)
    -- raw query
    local ret = pack(f(self, sql, ...))
    -- ends span
    span:finish()

    return unpack(ret)
  end

  connector.query = wrap
end


-- router
function _M.router()
  return tracer.start_span("router")
end

-- request (root span)
function _M.request(ctx)
  local req = kong.request
  local client = kong.client

  local method = get_method()
  local path = req.get_path()
  local span_name = method .. " " .. path
  local req_uri = ctx.request_uri or var.request_uri

  local start_time = ngx.ctx.KONG_PROCESSING_START
      and ngx.ctx.KONG_PROCESSING_START * 100000
      or time_ns()

  local active_span = tracer.start_span(span_name, {
    start_time_ns = start_time,
    attributes = {
      ["http.method"] = method,
      ["http.url"] = req_uri,
      ["http.host"] = var.http_host,
      ["http.scheme"] = ctx.scheme or var.scheme,
      ["http.flavor"] = ngx.req.http_version(),
      ["net.peer.ip"] = client.get_ip(),
    },
  })
  tracer.set_active_span(active_span)
end

-- balancer
function _M.balancer(ctx)
  local balancer_data = ctx.balancer_data
  if not balancer_data then
    return
  end

  local span
  local balancer_tries = balancer_data.tries
  local try_count = balancer_data.try_count
  local upstream_connect_time
  for i = 1, try_count do
    local try = balancer_tries[i]
    span = tracer.start_span("balancer try #" .. i, {
      kind = 3, -- client
      start_time_ns = try.balancer_start * 100000,
      attributes = {
        ["kong.balancer.state"] = try.state,
        ["http.status_code"] = try.code,
        ["net.peer.ip"] = try.ip,
        ["net.peer.port"] = try.port,
      }
    })

    if i < try_count then
      span:set_status(2)
    end

    -- last try
    if i == try_count then
      local upstream_finish_time = (ctx.KONG_BODY_FILTER_ENDED_AT or 0) * 100000
      span:finish(upstream_finish_time)
      return
    end

    if not upstream_connect_time then
      upstream_connect_time = split(var.upstream_connect_time, ",", "jo")
    end

    -- retry time
    if try.balancer_latency ~= nil then
      local try_upstream_connect_time = (upstream_connect_time[i] or 0) * 1000
      span:finish((try.balancer_start + try.balancer_latency + try_upstream_connect_time) * 100000)
      return
    end

    span:finish()
  end
end

local function plugin_callback(phase)
  local name_memo = {}

  return function(plugin)
    local plugin_name = plugin.name
    local name = name_memo[plugin_name]
    if not name then
      name = phase .. " phase: " .. plugin_name
      name_memo[plugin_name] = name
    end

    return tracer.start_span(name)
  end
end

_M.plugin_rewrite = plugin_callback("rewrite")
_M.plugin_access = plugin_callback("access")
_M.plugin_header_filter = plugin_callback("header_filter")

do
  local name_memo = {}
  function _M.dns_query(host, port)
    local name = name_memo[host]
    if not name then
      name = "DNS: " .. host
      name_memo[host] = name
    end

    return tracer.start_span(name)
  end
end

-- patch lua-resty-http
function _M.http_client()
  local http = require "resty.http"
  local request_uri = http.request_uri

  local function wrap(self, uri, params)
    local method = params and params.method or "GET"
    local attributes = new_tab(0, 5)
    attributes["http.url"] = uri
    attributes["http.method"] = method
    attributes["http.flavor"] = params and params.version or "1.1"
    attributes["http.user_agent"] = params and params.headers and params.headers["User-Agent"]
        or http._USER_AGENT

    local span = tracer.start_span("HTTP " .. method .. " " .. uri, {
      attributes = attributes,
    })

    local res, err = request_uri(self, uri, params)
    if res then
      attributes["http.status_code"] = res.status -- number
    else
      span:record_error(err)
    end
    span:finish()

    return res, err
  end

  http.request_uri = wrap
end

-- regsiter available_types
for k, _ in pairs(_M) do
  available_types[k] = true
end
_M.available_types = available_types


function _M.patch_dns_query(func)
  return function(host, port)
    local span = _M.dns_query(host, port)
    local ip_addr, res_port, try_list = func(host, port)

    if span then
      span:set_attribute("dns.record.ip", ip_addr)
      span:finish()
    end

    return ip_addr, res_port, try_list
  end
end

function _M.runloop_log_before(ctx)
  -- add balancer
  _M.balancer(ctx)

  local active_span = tracer.active_span()
  -- check root span type to avoid encounter error
  if active_span and type(active_span.finish) == "function" then
    local end_time = ctx.KONG_BODY_FILTER_ENDED_AT
                  and ctx.KONG_BODY_FILTER_ENDED_AT * 100000
    active_span:finish(end_time)
  end
end

local lazy_format_spans
do
  local lazy_mt = {
    __tostring = function(spans)
      local detail_logs = new_tab(#spans, 0)
      for i, span in ipairs(spans) do
        insert(detail_logs, "\nSpan #" .. i .. " name=" .. span.name)

        if span.end_time_ns then
          insert(detail_logs, " duration=" .. (span.end_time_ns - span.start_time_ns) / 100000 .. "ms")
        end

        if span.attributes then
          insert(detail_logs, " attributes=" .. cjson_encode(span.attributes))
        end
      end

      return concat(detail_logs)
    end
  }

  lazy_format_spans = function(spans)
    return setmetatable(spans, lazy_mt)
  end
end

function _M.runloop_log_after(ctx)
  -- Clears the span table and put back the table pool,
  -- this avoids reallocation.
  -- The span table MUST NOT be used after released.
  if type(ctx.KONG_SPANS) == "table" then
    ngx_log(ngx_DEBUG, _log_prefix, "collected " .. #ctx.KONG_SPANS .. " spans: ", lazy_format_spans(ctx.KONG_SPANS))

    for _, span in ipairs(ctx.KONG_SPANS) do
      if type(span) == "table" and type(span.release) == "function" then
        span:release()
      end
    end

    tablepool_release(POOL_SPAN_STORAGE, ctx.KONG_SPANS)
  end
end

function _M.init(config)
  local trace_types = config.opentelemetry_tracing
  local sampling_rate = config.opentelemetry_tracing_sampling_rate
  assert(type(trace_types) == "table" and next(trace_types))
  assert(sampling_rate >= 0 and sampling_rate <= 1)

  local enabled = trace_types[1] ~= "off"

  -- noop instrumentations
  -- TODO: support stream module
  if not enabled or ngx.config.subsystem == "stream" then
    for k, _ in pairs(available_types) do
      _M[k] = NOOP
    end

    -- remove root span generator
    _M.request = NOOP
  end

  if trace_types[1] ~= "all" then
    for k, _ in pairs(available_types) do
      if not tablex.find(trace_types, k) then
        _M[k] = NOOP
      end
    end
  end

  if enabled then
    -- global tracer
    tracer = pdk_tracer.new("instrument", {
      sampling_rate = sampling_rate,
    })
    tracer.set_global_tracer(tracer)
  end
end

return _M
