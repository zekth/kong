local nkeys = require "table.nkeys"
local isarray = require "table.isarray"

local t = {}
t["a"] = "test"
print(isarray(t))