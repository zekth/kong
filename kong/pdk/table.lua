-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--- Utilities for Lua tables.
--
-- @module kong.table


---
-- Returns a table with a pre-allocated number of slots in its array and hash
-- parts.
--
-- @function kong.table.new
-- @tparam[opt] number narr Specifies the number of slots to pre-allocate
-- in the array part.
-- @tparam[opt] number nrec Specifies the number of slots to pre-allocate in
-- the hash part.
-- @treturn table The newly created table.
-- @usage
-- local tab = kong.table.new(4, 4)
local new_tab = require "table.new"

---
-- Clears all array and hash parts entries from a table.
--
-- @function kong.table.clear
-- @tparam table tab The table to be cleared.
-- @return Nothing.
-- @usage
-- local tab = {
--   "hello",
--   foo = "bar"
-- }
--
-- kong.table.clear(tab)
--
-- kong.log(tab[1]) -- nil
-- kong.log(tab.foo) -- nil
local clear_tab = require "table.clear"


--- Merges the contents of two tables together, producing a new one.
-- The entries of both tables are copied non-recursively to the new one.
-- If both tables have the same key, the second one takes precedence.
-- If only one table is given, it returns a copy.
-- @function kong.table.merge
-- @tparam[opt] table t1 The first table.
-- @tparam[opt] table t2 The second table.
-- @treturn table The (new) merged table.
-- @usage
-- local t1 = {1, 2, 3, foo = "f"}
-- local t2 = {4, 5, bar = "b"}
-- local t3 = kong.table.merge(t1, t2) -- {4, 5, 3, foo = "f", bar = "b"}
local function merge_tab(t1, t2)
  local res = {}
  if t1 then
    for k,v in pairs(t1) do
      res[k] = v
    end
  end
  if t2 then
    for k,v in pairs(t2) do
      res[k] = v
    end
  end
  return res
end


local function new(self)
  return {
    new = new_tab,
    clear = clear_tab,
    merge = merge_tab,
  }
end


return {
  new = new,
}
