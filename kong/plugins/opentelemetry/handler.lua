local subsystem = ngx.config.subsystem
local load_pb = require("kong.plugins.opentelemetry.otlp").load_pb
local to_pb = require("kong.plugins.opentelemetry.otlp").to_pb
local to_otlp_span = require("kong.plugins.opentelemetry.otlp").to_otlp_span
local otlp_export_request = require("kong.plugins.opentelemetry.otlp").otlp_export_request
local new_tab = require "table.new"
local insert = table.insert
local ngx = ngx
local inspect = require "inspect"
local kong = kong
local http = require "resty.http"
local fmt = string.format

local OpenTelemetryHandler = {
  VERSION = "0.0.1",
  -- We want to run first so that timestamps taken are at start of the phase
  -- also so that other plugins might be able to use our structures
  PRIORITY = 100000,
}

-- cache exporter instances
local exporter_cache = setmetatable({}, { __mode = "k" })


function OpenTelemetryHandler:init_worker()
  assert(load_pb())
end

function OpenTelemetryHandler:access(conf)
  local ngx_ctx = ngx.ctx
  local route = kong.router.get_route()
  local service = kong.router.get_service()

  local span_name = route and route.name or kong.request.get_path()

  local span = kong.tracer:start_span(ngx_ctx, fmt("access %s", span_name), 2, ngx.ctx.KONG_PROCESSING_START * 1000000)
  span:set_attribute("node", kong.node.get_hostname())
  span:set_attribute("http.host", kong.request.get_host())
  span:set_attribute("http.version", kong.request.get_http_version())
  span:set_attribute("http.method", kong.request.get_method())
  span:set_attribute("http.path", kong.request.get_path())

  if route and service then
    span:set_attribute("route.name", route.name)
    span:set_attribute("service.name", service.name)    
  end
end


function OpenTelemetryHandler:body_filter()
  if not ngx.arg[2] then
    return
  end

  local span = kong.tracer:get_current_span(ngx.ctx)
  if span ~= nil then
    -- ngx.log(ngx.ERR, "--------------end")
    span:finish()
  end
end


local function http_send_spans(premature, conf, spans)
  if premature then
    return
  end

  local req = assert(otlp_export_request(spans))
  ngx.log(ngx.NOTICE, inspect(req))

  local pb_data = assert(to_pb(req))

  local httpc = http.new()
  local headers = {
    ["Content-Type"] = "application/x-protobuf",
  }

  if conf.http_headers ~= nil then
    for k, v in pairs(conf.http_headers) do
      headers[k] = v and v[1]
    end
  end

  local res, err = httpc:request_uri(conf.http_endpoint, {
    method = "POST",
    body = pb_data,
    headers = headers,
    ssl_verify = false,
  })
  if not res then
    ngx.log(ngx.ERR, "request failed: ", err)
    return
  end

  if res.status ~= 200 then
    ngx.log(ngx.ERR, "request failed: ", res.body)
  end

  -- ngx.log(ngx.NOTICE, "sent single trace, status: ", res.status)
end

local function attach_balancer_data(ctx)
  local balancer_data = ngx.ctx.balancer_data
  if not balancer_data then
    return
  end

  local balancer_tries = balancer_data.tries
  local hostname = balancer_data.hostname
  for i = 1, balancer_data.try_count do
    local try = balancer_tries[i]
    local span = kong.tracer:start_span(ctx, fmt("upstream %s", hostname), 3, try.balancer_start * 1000000)

    span:set_attribute("peer.service", hostname)
    if try.balancer_latency ~= nil then
      span:finish((try.balancer_start + try.balancer_latency) * 1000000)
    else
      span:finish()
    end
  end

end

-- collect trace and spans
function OpenTelemetryHandler:log(conf) -- luacheck: ignore 212
  -- !!!! balancer
  local balancer_span = kong.tracer:start_span(ngx.ctx, "upstream", 1, ngx.ctx.KONG_BALANCER_START * 1000000)
  balancer_span:finish(ngx.ctx.KONG_BODY_FILTER_ENDED_AT * 1000000)

  --- !!! tracer
  local test_span = kong.tracer:start_span(ngx.ctx, "tracer1", 1)
  test_span:set_attribute("trace_context", "log")
  test_span:finish()

  local sec = kong.tracer:start_span(ngx.ctx, "tracer1", 1)
  sec:finish()

  -- attach_balancer_data(ngx.ctx)
  local spans = kong.tracer:spans_from_ctx()
  if type(spans) ~= "table" or #spans == 0 then
    ngx.log(ngx.NOTICE, "skip empty spans")
    return
  end

  ngx.timer.at(0, http_send_spans, conf, spans)
end


return OpenTelemetryHandler
