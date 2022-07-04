local conf_loader = require "kong.conf_loader"
local DB = require "kong.db"
local helpers = require "spec.helpers"
local inspect = require "inspect"

local conf = conf_loader()
local db = assert(DB.new(conf))
assert(db:init_connector())

describe("2.8.1 to master upgrade path", function()
            for _, strategy in helpers.each_strategy() do
               if strategy == 'postgres' then
                  describe("upgrade #before", function()
                              it("works", function()
                                    local res, err = db.connector:query('select * from parameters')
                                    print(inspect(res))
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
               end
            end
end)
