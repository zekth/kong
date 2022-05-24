local insert = table.insert

local t = {}
t[0] = 0
local function target()
  local len = t[0] + 1
  t[len] = "test"
  t[0] = len
end

for i = 1, 10000 do
  target()
end

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