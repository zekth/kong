local unpack = table.unpack
local pack = table.pack


local function wrap1(func)
  local ret = { func() }
  return unpack(ret)
end

local function wrap2(func)
  local ret = pack(func())
  return unpack(ret)
end

local function callback()
  ngx.sleep(1)
end

ngx.update_time()
local a = ngx.now()

wrap1(callback)

ngx.update_time()
print(ngx.now() - a)

ngx.update_time()
a = ngx.now()
wrap2(callback)

ngx.update_time()
print(ngx.now() - a)