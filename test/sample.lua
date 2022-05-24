local utils       = require "kong.tools.utils"
local rand_bytes  = utils.get_rand_bytes
local bit         = require "bit"
local lshift      = bit.lshift
local rshift      = bit.rshift
local ffi         = require "ffi"
local fmt         = string.format
local math_random = math.random
local ffi_cast = ffi.cast
local ffi_string = ffi.string

local trace_id = rand_bytes(16)
local str = ffi.cast("const char*", trace_id)

local upper_bound = 0.7 * tonumber(lshift(ffi.cast("uint64_t", 1), 63))

print(fmt("%d", upper_bound))

local function acc(t)
  local n = ffi_cast("uint64_t*", ffi_string(t, 8))[0]
  n = rshift(n, 1)
  return tonumber(n)
end

local tt = ngx.decode_base64("pfJS/7R92OafoKWaK4e5cw==")
print(tt)
print("int: ", ffi.cast("uint64_t*", ffi.string(tt, 8))[0])
print("int: ", ffi.cast("uint64_t*", ffi.string(tt, 8))[0])
print("int: ", ffi.cast("uint64_t*", ffi.string(tt, 8))[0])
print(fmt("%d", acc(tt)))


local function target_rand()
  return math_random() < 0.7
end

local function target()
  trace_id = rand_bytes(16)
  return acc(trace_id) < upper_bound
end

local true_num = 0
for i = 1, 10000 do
  if target() == true then
    true_num = true_num + 1
  end
end
print(true_num)


-- benchmark
t = {}
t[0] = 0
ngx.update_time()
local begin = ngx.now()

local N = 1e7
for i = 1, N do
  target()
end


ngx.update_time()
print("elapsed: ", (ngx.now() - begin) / N)
