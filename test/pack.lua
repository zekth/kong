local pack = table.pack
local unpack = table.unpack


local function hello()
    return "hello", 1, nil, 0, 2
end

local ret = pack(hello())


print(ret)

print(ret[4])

print(unpack(ret))