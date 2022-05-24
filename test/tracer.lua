local pdk_tracer = require "kong.pdk.tracing".new()
local base = require "resty.core.base"
local fmt = string.format
local start_span = pdk_tracer.start_span
local tablepool = require "tablepool"
local tablepool_release = tablepool.release
local hooks = require "kong.hooks"
local run_hook = hooks.run_hook

local tracer = pdk_tracer.new("tracer")

hooks.register_hook("test:pre", function ()
  return tracer.start_span("test")
end)

hooks.register_hook("test:post", function (span)
  span:finish()
  span:release()
end)

local function target()
  local span = tracer.start_span("test")
  span:finish()
  span:release()
end

local function target2()
  local span = run_hook("test:pre")
  run_hook("test:post", span)
end

for i = 1, 10000 do
  target()
  target2()
end

do
  ngx.update_time()
  local begin = ngx.now()

  local N = 1e7
  N = 10000
  for i = 1, N do
    target()
  end


  ngx.update_time()
  print("1 elapsed: ", (ngx.now() - begin) / N)
end

do
  ngx.update_time()
  local begin = ngx.now()

  local N = 1e7
  N = 10000
  for i = 1, N do
    target2()
  end


  ngx.update_time()
  print("2 elapsed: ", (ngx.now() - begin) / N)
end
