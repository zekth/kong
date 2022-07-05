local conf_loader = require "kong.conf_loader"
local DB = require "kong.db"
local helpers = require "spec.helpers"
local inspect = require "inspect"
local say = require "say"

local conf = conf_loader()
local db = assert(DB.new(conf))
assert(db:init_connector())

local function table_has_column(state, arguments)
   local table = arguments[1]
   local column_name = arguments[2]
   local type = arguments[3]
   -- The type argument is not yet normalized.  No problem for 'text'
   -- columns, but won't work for 'int' (Cassandra) vs. 'integer'
   -- (Postgres) yet.
   local res, err
   if conf['database'] == 'cassandra' then
      res, err = db.connector:query(string.format(
                                       "select *"
                                       .. " from system_schema.columns"
                                       .. " where table_name = '%s'"
                                       .. "   and column_name = '%s'"
                                       .. "   and type = '%s'"
                                       .. " allow filtering",
                                       table, column_name, type))
   elseif conf['database'] == 'postgres' then
      res, err = db.connector:query(string.format(
                                       "select true"
                                       .. " from information_schema.columns"
                                       .. " where table_schema = 'public'"
                                       .. "   and table_name = '%s'"
                                       .. "   and column_name = '%s'"
                                       .. "   and data_type = '%s'",
                                       table, column_name, type))
   else
      return false
   end
   if err then
      return false
   end
   return not(not(res[1]))
end

say:set("assertion.table_has_column.positive", "Expected table %s to have column %s with type %s")
say:set("assertion.table_has_column.negative", "Expected table %s not to have column %s with type %s")
assert:register("assertion", "table_has_column", table_has_column, "assertion.table_has_column.positive", "assertion.table_has_column.negative")

describe("2.8.1 to master upgrade path", function()
            describe("upgrade #before", function()
                        it("works", function()
                              assert.table_has_column("targets", "cache_key", "text")
                              assert.table_has_column("upstreams", "hash_on_query_arg", "text")
                              assert.table_has_column("upstreams", "hash_fallback_query_arg", "text")
                              assert.table_has_column("upstreams", "hash_on_uri_capture", "text")
                              assert.table_has_column("upstreams", "hash_fallback_uri_capture", "text")
                        end)
            end)
            describe("upgrade #migrating", function()
                        it("works", function()
                              assert.truthy(true)
                        end)
            end)
            describe("upgrade #after", function()
                        it("works", function()
                        end)
            end)
end)
