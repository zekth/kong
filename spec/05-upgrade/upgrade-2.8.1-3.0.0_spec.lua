local upgrade_helpers = require "spec/upgrade_helpers"

describe("database migration #before", function()
            it("has created the expected new columns", function()
                  assert.table_has_column("targets", "cache_key", "text")
                  assert.table_has_column("upstreams", "hash_on_query_arg", "text")
                  assert.table_has_column("upstreams", "hash_fallback_query_arg", "text")
                  assert.table_has_column("upstreams", "hash_on_uri_capture", "text")
                  assert.table_has_column("upstreams", "hash_fallback_uri_capture", "text")
            end)
end)

describe("vault related data migration", function()
            describe("upgrade #before", function()
                        -- nothing to test here as of now
            end)
            describe("upgrade #migrating", function()
                        -- nothing to test here as of now
            end)
            describe("upgrade #after", function()
                        -- nothing to test here as of now
            end)
end)
