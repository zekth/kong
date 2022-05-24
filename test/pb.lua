require "kong.plugins.opentelemetry.proto"

local otlp = require "kong.plugins.opentelemetry.otlp"
local utils = require "kong.tools.utils"
local pb = require "pb"

local rand_bytes = utils.get_rand_bytes
local time_ns = utils.time_ns

local pb_encode_span = function(data)
  return assert(pb.encode("opentelemetry.proto.trace.v1.Span", data))
end

local pb_decode_span = function(data)
  return assert(pb.decode("opentelemetry.proto.trace.v1.Span", data))
end

local test_span = {
  name = "full-span",
  trace_id = rand_bytes(16),
  span_id = rand_bytes(8),
  parent_id = rand_bytes(8),
  start_time_ns = time_ns(),
  end_time_ns = time_ns() + 1000,
  should_sample = true,
  attributes = {
    foo = "bar",
    test = true,
    version = 0.1,
  },
  events = {
    {
      name = "evt1",
      time_ns = time_ns(),
      attributes = {
        debug = true,
      }
    }
  },
}

local pb_span = otlp.transform_span(test_span)

local function target()
  pb_encode_span(pb_span)
end

for i = 1, 10000 do
  target()
end

ngx.update_time()
local begin = ngx.now()

local N = 1000000
for i = 1, N do
  target()
end


ngx.update_time()
local per_time = (ngx.now() - begin) / N * 1000
print("elapsed: ", tostring(per_time), " ms")

