local say = require "say"
local assert = require "luassert"

local helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"
local DB = require "kong.db"

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

local function proxy_client()
   return helpers.http_client({
         host = os.getenv("TARGET_HOST"),
         port = 8000,
         timeout = 60000})
end

local function admin_client()
   print("admin talking to " .. os.getenv("TARGET_HOST") .. ":" .. 8001)
   return helpers.http_client({
         host = os.getenv("TARGET_HOST"),
         port = 8001,
         timeout = 60000})
end

return {
   admin_client = admin_client,
   proxy_client = proxy_client
}
