local spec_helpers = require "spec.helpers"
local utils       = require "kong.tools.utils"
local bit = require "bit"


local rbac
local kong = kong


for _, strategy in spec_helpers.each_strategy() do
describe("(#" .. strategy .. ")", function()
  local db, bp


  setup(function()
    package.loaded["kong.rbac"] = nil

    bp, db = spec_helpers.get_db_utils()

    rbac = require "kong.rbac"
  end)


  describe("RBAC", function()
    setup(function()
      math.randomseed(ngx.now())
    end)

    describe("._bitfield_all_actions", function()
      local all_actions = rbac._bitfield_all_actions
      for perm_name, perm_bit in pairs(rbac.actions_bitfields) do
        it("has '" .. perm_name .. "' permissions", function()
          assert.equals(perm_bit, bit.band(perm_bit, all_actions))
        end)
      end
    end)

    describe("._resolve_role_entity_permissions", function()
      local role_id, entity_id

      setup(function()
        local u = utils.uuid
        role_id = bp.rbac_roles:insert().id
        entity_id = u()

        assert(db.rbac_role_entities:insert({
          role = { id = role_id },
          entity_id = entity_id,
          entity_type = "entity",
          actions = 0x1,
          negative = false,
        }))
      end)

      teardown(function()
        db:truncate()
      end)

      it("returns a map given a role", function()
        local map = rbac._resolve_role_entity_permissions({
          { id = role_id },
        })

        assert.equals(0x1, map[entity_id])
      end)

      describe("prioritizes explicit negative permissions", function()
        local role_id2 = bp.rbac_roles:insert().id

        setup(function()
          assert(db.rbac_role_entities:insert({
            role = { id = role_id2 },
            entity_id = entity_id,
            entity_type = "entity",
            actions = 0x1,
            negative = true,
          }))
        end)

        it("", function()
          local map = rbac._resolve_role_entity_permissions({
            { id = role_id },
            { id = role_id2 },
          })

          -- role_id  has 1 positive read (1) permission
          -- role_id2 has 1 negative read (1 << 4) permission
          -- (1 | 1 << 4) == 17
          assert.equals(17, map[entity_id])
        end)

        it("regardless of role order", function()
          local map = rbac._resolve_role_entity_permissions({
            { id = role_id2 },
            { id = role_id },
          })

          -- role_id  has 1 positive read (1) permission
          -- role_id2 has 1 negative read (1 << 4) permission
          -- (1 | 1 << 4) == 17
          assert.equals(17, map[entity_id])
        end)
      end)
    end)

    describe(".resolve_role_endpoint_permissions", function()
      local role_ids = {}

      setup(function()
        package.loaded["kong.rbac"] = nil
        table.insert(role_ids, bp.rbac_roles:insert().id)
        assert(db.rbac_role_endpoints:insert({
          role = { id = role_ids[#role_ids] },
          workspace = "foo",
          endpoint = "/bar",
          actions = 0x1,
          negative = false,
        }))

        table.insert(role_ids, bp.rbac_roles:insert().id)
        assert(db.rbac_role_endpoints:insert({
          role = { id = role_ids[#role_ids] },
          workspace = "foo",
          endpoint = "/bar",
          actions = 0x1,
          negative = true,
        }))

        assert(db.rbac_role_endpoints:insert({
          role = { id = role_ids[#role_ids] },
          workspace = "baz",
          endpoint = "/bar",
          actions = 0x5,
          negative = false,
        }))
      end)

      teardown(function()
        db:truncate()
      end)

      it("returns a permissions map for a given role", function()
        local map = rbac.resolve_role_endpoint_permissions({
          { id = role_ids[1] },
        })

        assert.equals(0x1, map.foo["/foo/bar"])
      end)

      it("returns a map and negative permissions map given a role", function()
        local map, nmap = rbac.resolve_role_endpoint_permissions({
          { id = role_ids[1] },
        })
        assert(map)
        assert(nmap)

        for workspace in pairs(map) do
          for endpoint, actions in pairs(map[workspace]) do
            assert.is_boolean(nmap[endpoint])
          end
        end
      end)

      it("returns a permissions map for multiple roles", function()
        local map = rbac.resolve_role_endpoint_permissions({
          { id = role_ids[1] },
          { id = role_ids[2] },
        })

        assert.equals(0x11, map.foo["/foo/bar"])
      end)

      it("returns separate permissions under separate workspaces", function()
        local map = rbac.resolve_role_endpoint_permissions({
          { id = role_ids[2] },
        })

        assert.equals(0x11,map.foo["/foo/bar"])
        assert.equals(0x5, map.baz["/baz/bar"])
      end)
    end)
  end)

  describe(".authorize_request_endpoint", function()
    describe("authorizes a request", function()
      describe("workspace/endpoint", function()
        it("(positive)", function()
          assert.equals(true, rbac.authorize_request_endpoint(
            { foo = { ["bar"] = 0x1 } },
            "foo",
            "bar",
            "/bar",
            rbac.actions_bitfields.read
          ))
        end)
        it("(endpoint with workspace)", function()
          assert.equals(true, rbac.authorize_request_endpoint(
            { foo = { ["bar"] = 0x1 } },
            "foo",
            "/foo/bar",
            "bar",
            rbac.actions_bitfields.read
          ))
        end)
        it("(normalized route)", function()
          assert.equals(true, rbac.authorize_request_endpoint(
            { foo = { ["bar"] = 0x1 } },
            "foo",
            "bar",
            "/foo/*",
            rbac.actions_bitfields.read
          ))
        end)
        it("(route with workspace)", function()
          assert.equals(true, rbac.authorize_request_endpoint(
            { foo = { ["bar"] = 0x1 } },
            "foo",
            "bar",
            "/foo/bar/",
            rbac.actions_bitfields.read
          ))
        end)
        it("(endpoint with wildcards)", function()
          assert.equals(true, rbac.authorize_request_endpoint(
            { foo = { ["/bar/*/*"] = 0x1 } },
            "foo",
            "/bar/baz/quux",
            "/foo/bar/baz/quux",
            rbac.actions_bitfields.read
          ))
        end)
        it("(endpoint with wildcards but different depth)", function()
          assert.equals(false, rbac.authorize_request_endpoint(
            { foo = { ["/bar/*"] = 0x1 } },
            "foo",
            "/bar/baz/quux",
            "/foo/bar/baz/quux",
            rbac.actions_bitfields.read
          ))
        end)
        it("(hierarchical path)", function()
          local map = { foo = { ["/services/test/plugins/"] = 0x1 } }
          assert.equals(true, rbac.authorize_request_endpoint(
            map,
            "foo",
            "/services/test/plugins/",
            "_workspace/services/:services_name/plugins/",
            rbac.actions_bitfields.read
          ))
        end)
        it("(hierarchical path with wildcard)", function()
          local map = { foo = { ["/services/*/plugins"] = 0x1 } }
          assert.equals(true, rbac.authorize_request_endpoint(
            map,
            "foo",
            "/services/test/plugins",
            "/services/:service_name/plugins",
            rbac.actions_bitfields.read
          ))
        end)
        pending("(hierarchical path with wildcard ending with slash)", function()
          local map = { foo = { ["/services/*/plugins/"] = 0x1 } }
          assert.equals(true, rbac.authorize_request_endpoint(
                          map,
                          "foo",
                          "/services/test/plugins/",
                          "/services/:service_name/plugins",
                          rbac.actions_bitfields.read))
        end)
        it("(negative override)", function()
          assert.equals(false, rbac.authorize_request_endpoint(
            { foo = { bar = 0x11 } },
            "foo",
            "/bar",
            "/bar",
            rbac.actions_bitfields.read
          ))
        end)
        it("(empty)", function()
          assert.equals(false, rbac.authorize_request_endpoint(
            { foo = { baz = 0x1 } },
            "foo",
            "/bar",
            "/bar",
            rbac.actions_bitfields.read
          ))
        end)
        it("adding super-admin to a user with admin role", function()
          -- no workspace attached and no access to rbac paths
          assert.equals(false, rbac.authorize_request_endpoint(
            {
              ["*"] = {
                ["*"] = 15,
                ["/*/rbac/*"] = 255,
                ["/*/rbac/*/*"] = 255,
                ["/*/rbac/*/*/*"] = 255,
                ["/*/rbac/*/*/*/*"] = 255,
                ["/*/rbac/*/*/*/*/*"] = 255
              }
            },
            "default",
            "/rbac/users/bob/permissions",
            "/rbac/users/:name_or_id/permissions",
            rbac.actions_bitfields.read
          ))
          --  workspace attached and no access to rbac paths
          assert.equals(false, rbac.authorize_request_endpoint(
            {
              ["*"] = {
                ["*"] = 15,
                ["/*/rbac/*"] = 255,
                ["/*/rbac/*/*"] = 255,
                ["/*/rbac/*/*/*"] = 255,
                ["/*/rbac/*/*/*/*"] = 255,
                ["/*/rbac/*/*/*/*/*"] = 255
              }
            },
            "foo",
            "/foo/rbac/users/bob/permissions",
            "workspace_/rbac/users/:name_or_id/permissions",
            rbac.actions_bitfields.read
          ))

          --  workspace foo attached and no access to rbac paths
          assert.equals(false, rbac.authorize_request_endpoint(
            {
              ["foo"] = {
                ["*"] = 15,
                ["/foo/rbac/*"] = 255,
                ["/foo/rbac/*/*"] = 255,
                ["/foo/rbac/*/*/*"] = 255,
                ["/foo/rbac/*/*/*/*"] = 255,
                ["/foo/rbac/*/*/*/*/*"] = 255
              }
            },
            "foo",
            "/foo/rbac/users/bob/permissions",
            "workspace_/rbac/users/:name_or_id/permissions",
            rbac.actions_bitfields.read
          ))

          --  workspace foo attached and access to workspace_/rbac/users/:name_or_id/permissions paths
          assert.equals(true, rbac.authorize_request_endpoint(
            {
              ["foo"] = {
                ["*"] = 15,
                ["/foo/rbac/*"] = 255,
                ["/foo/rbac/*/*"] = 255,
                ["/foo/rbac/*/*/*"] = 15,
                ["/foo/rbac/*/*/*/*"] = 255,
                ["/foo/rbac/*/*/*/*/*"] = 255
              }
            },
            "foo",
            "/foo/rbac/users/bob/permissions",
            "workspace_/rbac/users/:name_or_id/permissions",
            rbac.actions_bitfields.read
          ))

          --  workspace default attached and and no access to default rbac paths
          assert.equals(false, rbac.authorize_request_endpoint(
            {
              ["foo"] = {
                ["*"] = 15,
                ["/foo/rbac/*"] = 255,
                ["/foo/rbac/*/*"] = 255,
                ["/foo/rbac/*/*/*"] = 255,
                ["/foo/rbac/*/*/*/*"] = 255,
                ["/foo/rbac/*/*/*/*/*"] = 255
              }
            },
            "default",
            "/default/rbac/users/bob/permissions",
            "workspace_/rbac/users/:name_or_id/permissions",
            rbac.actions_bitfields.read
          ))

          --  any workspace foo attached and access to workspace_/rbac/users/:name_or_id/permissions paths\
          assert.equals(true, rbac.authorize_request_endpoint(
            {
              ["*"] = {
                ["*"] = 15,
                ["/*/rbac/*"] = 255,
                ["/*/rbac/*/*"] = 255,
                ["/*/rbac/*/*/*"] = 15,
                ["/*/rbac/*/*/*/*"] = 255,
                ["/*/rbac/*/*/*/*/*"] = 255
              }
            },
            "default",
            "/rbac/users/bob/permissions",
            "workspace_/rbac/users/:name_or_id/permissions",
            rbac.actions_bitfields.read
          ))

          assert.equals(true, rbac.authorize_request_endpoint(
            {
              ["*"] = {
                ["*"] = 15,
                ["/*/rbac/*"] = 255,
                ["/*/rbac/*/*"] = 255,
                ["/*/rbac/*/*/*"] = 15,
                ["/*/rbac/*/*/*/*"] = 255,
                ["/*/rbac/*/*/*/*/*"] = 255
              }
            },
            "default",
            "/default/rbac/users/bob/permissions",
            "workspace_/rbac/users/:name_or_id/permissions",
            rbac.actions_bitfields.read
          ))

          assert.equals(true, rbac.authorize_request_endpoint(
            {
              ["*"] = {
                ["*"] = 15,
                ["/*/rbac/*"] = 255,
                ["/*/rbac/*/*"] = 255,
                ["/*/rbac/*/*/*"] = 15,
                ["/*/rbac/*/*/*/*"] = 255,
                ["/*/rbac/*/*/*/*/*"] = 255
              }
            },
            "foo",
            "/foo/rbac/users/bob/permissions",
            "workspace_/rbac/users/:name_or_id/permissions",
            rbac.actions_bitfields.read
          ))
        end)
      end)
      describe("workspace/*", function()
        it("(positive)", function()
          assert.equals(true, rbac.authorize_request_endpoint(
            { foo = { ["*"] = 0x1 } },
            "foo",
            "/bar",
            "/bar",
            rbac.actions_bitfields.read
          ))
        end)
        it("(negative)", function()
          assert.equals(false, rbac.authorize_request_endpoint(
            { foo = { ["*"] = 0x11 } },
            "foo",
            "/bar",
            "/foo/bar/",
            rbac.actions_bitfields.read
          ))
        end)
        it("does not override specific endpoint", function()
          assert.equals(true, rbac.authorize_request_endpoint(
            { foo = { ["*"] = 0x11, ["bar"] = 0x1 } },
            "foo",
            "bar",
            "/foo/bar/",
            rbac.actions_bitfields.read
          ))
        end)
      end)
      describe("*/endpoint", function()
        it("(positive)", function()
          assert.equals(true, rbac.authorize_request_endpoint(
            { ["*"] = { bar = 0x1 } },
            "foo",
            "bar",
            "/foo/bar/",
            rbac.actions_bitfields.read
          ))
        end)
        it("(negative)", function()
          assert.equals(false, rbac.authorize_request_endpoint(
            { ["*"] = { bar = 0x11 } },
            "foo",
            "bar",
            "/foo/bar/",
            rbac.actions_bitfields.read
          ))
        end)
        it("(empty(", function()
          assert.equals(true, rbac.authorize_request_endpoint(
            { ["*"] = { bar = 0x1 } },
            "baz",
            "bar",
            "/baz/bar/",
            rbac.actions_bitfields.read
          ))
        end)
        it("does not override specific workspace", function()
          assert.equals(true, rbac.authorize_request_endpoint(
            { foo = { ["*"] = 0x11, bar = 0x1 }, ["*"] = { bar = 0x1 } },
            "foo",
            "bar",
            "/foo/bar/",
            rbac.actions_bitfields.read
          ))
          assert.equals(false, rbac.authorize_request_endpoint(
            { foo = { ["*"] = 0x11, bar = 0x1 }, ["*"] = { bar = 0x1 } },
            "foo",
            "baz",
            "/foo/baz/",
            rbac.actions_bitfields.read
          ))
        end)
      end)
      describe("*/*", function()
        it("(positive)", function()
          assert.equals(true, rbac.authorize_request_endpoint(
            { ["*"] = { ["*"] = 0x1 } },
            "foo",
            "bar",
            "/foo/bar/",
            rbac.actions_bitfields.read
          ))
        end)
        it("(negative)", function()
          assert.equals(false, rbac.authorize_request_endpoint(
            { ["*"] = { ["*"] = 0x11 } },
            "foo",
            "bar",
            "/foo/bar/",
            rbac.actions_bitfields.read
          ))
        end)
        it("does not override a specific workspace/endpoint", function()
          assert.equals(false, rbac.authorize_request_endpoint(
            { ["*"] = { ["*"] = 0x1 }, foo = { bar = 0x11 } },
            "foo",
            "bar",
            "/foo/bar/",
            rbac.actions_bitfields.read
          ))
          assert.equals(true, rbac.authorize_request_endpoint(
            { ["*"] = { ["*"] = 0x1 }, foo = { bar = 0x11 } },
            "baz",
            "bar",
            "/baz/bar/",
            rbac.actions_bitfields.read
          ))
        end)
      end)
    end)
    describe("treats bit vectors appropriately", function()
      it("given multiple permissive bits", function()
        assert.equals(true, rbac.authorize_request_endpoint(
          { foo = { bar = 0x1 } },
          "foo",
          "bar",
          "/foo/bar/",
          rbac.actions_bitfields.read
        ))
        assert.equals(false, rbac.authorize_request_endpoint(
          { foo = { bar = 0x1 } },
          "foo",
          "bar",
          "/foo/bar/",
          rbac.actions_bitfields.create
        ))
        assert.equals(true, rbac.authorize_request_endpoint(
          { foo = { bar = 0x3 } },
          "foo",
          "bar",
          "/foo/bar/",
          rbac.actions_bitfields.create
        ))
      end)
      it("given permissive and denial bits", function()
        assert.equals(false, rbac.authorize_request_endpoint(
          { foo = { bar = 0x12 } },
          "foo",
          "bar",
          "/foo/bar/",
          rbac.actions_bitfields.read
        ))
        assert.equals(true, rbac.authorize_request_endpoint(
          { foo = { bar = 0x12 } },
          "foo",
          "bar",
          "/foo/bar/",
          rbac.actions_bitfields.create
        ))
      end)
    end)
  end)
  describe("._authorize_request_entity", function()
    it("returns true on bit match", function()
      assert.equals(true, rbac._authorize_request_entity(
        { foo = 0x1 },
        "foo",
        0x1
      ))
    end)

    it("returns true when multiple bits are assigned", function()
      for i = 1, 4 do
        assert.equals(true, rbac._authorize_request_entity(
          { foo = 0xf },
          "foo",
          (2 ^ i) - 1
        ))
      end
    end)

    it("returns false when no bit is unset", function()
      assert.equals(false, rbac._authorize_request_entity(
        { foo = 0x1 },
        "foo",
        0x2
      ))
    end)

    it("returns false when no key is present", function()
      assert.equals(false, rbac._authorize_request_entity(
        { foo = 0x1 },
        "bar",
        0x1
      ))
      assert.equals(false, rbac._authorize_request_entity(
        {},
        "bar",
        0x1
      ))
    end)
  end)
  describe("check_cascade", function()
    local entities
    setup(function()
      kong.configuration= {
        rbac = "both",
      }
      entities = {
        ["table1"] = {
          entities = {
            { id = "t1e1" },
            { id = "t1e2" },
          },
          schema = {
            ["t1s1"] = {},
            ["t1s2"] = {},
            primary_key = { "id" },
          }
        },
        ["table2"] = {
          entities = {
            { name = "t2e1" },
            { name = "t2e2" },
          },
          schema = {
            ["t2s1"] = {},
            ["t2s2"] = {},
            primary_key = { "name" },
          }
        }
      }
    end)
    teardown(function()
      kong.configuration = nil
    end)

    it("all entities allowed", function()
      local rbac_ctx = {
        user = nil,
        roles = {},
        action = 0x1,
        entities_perms = {
          t1e1 = 0x1,
          t1e2 = 0x1,
          t2e1 = 0x1,
          t2e2 = 0x1,
        },
        endpoints_perms = nil,
      }
      assert.equals(true, rbac.check_cascade(entities, rbac_ctx))
    end)
    it("one entity not allowed", function()
      local rbac_ctx = {
        user = nil,
        roles = {},
        action = 0x1,
        entities_perms = {
          t1e1 = 0x1,
          t1e2 = 0x1,
          t2e1 = 0x2,
          t2e2 = 0x1,
        },
        endpoints_perms = nil,
      }
      assert.equals(false, rbac.check_cascade(entities, rbac_ctx))
    end)
    it("rbac off", function()
      kong.configuration= {
        rbac = "off",
      }
      assert.equals(true, rbac.check_cascade(entities, nil))
    end)
  end)
  describe("readable_entities_permissions", function()
    local u, role_id, entity_id
    setup(function()
      u = utils.uuid
    end)

    teardown(function()
      db:truncate()
    end)

    it("each action", function()
      role_id = bp.rbac_roles:insert().id
      entity_id = u()

      assert(db.rbac_role_entities:insert({
        role = { id = role_id },
        entity_id = tostring(entity_id),
        entity_type = "entity",
        actions = 0x01,
        negative = false,
      }))
      local map = rbac.readable_entities_permissions({
        { id = role_id },
      })
      assert.same(rbac.readable_action(0x1), map[entity_id].actions[1])

      role_id = bp.rbac_roles:insert().id
      entity_id = u()

      assert(db.rbac_role_entities:insert({
        role = { id = role_id },
        entity_id = entity_id,
        entity_type = "entity",
        actions = 0x02,
        negative = false,
      }))
      local map = rbac.readable_entities_permissions({
        { id = role_id },
      })
      assert.equals(rbac.readable_action(0x2), map[entity_id].actions[1])

      role_id = bp.rbac_roles:insert().id
      entity_id = u()

      assert(db.rbac_role_entities:insert({
        role = { id = role_id },
        entity_id = entity_id,
        entity_type = "entity",
        actions = 0x04,
        negative = false,
      }))
      local map = rbac.readable_entities_permissions({
        { id = role_id },
      })
      assert.equals(rbac.readable_action(0x4), map[entity_id].actions[1])

      role_id = bp.rbac_roles:insert().id
      entity_id = u()

      assert(db.rbac_role_entities:insert({
        role = { id = role_id },
        entity_id = entity_id,
        entity_type = "entity",
        actions = 0x08,
        negative = false,
      }))
      local map = rbac.readable_entities_permissions({
        { id = role_id },
      })
      assert.equals(rbac.readable_action(0x08), map[entity_id].actions[1])
    end)
    it("multiple permission", function()
      role_id = bp.rbac_roles:insert().id
      entity_id = u()

      assert(db.rbac_role_entities:insert({
        role = { id = role_id },
        entity_id = entity_id,
        entity_type = "entity",
        actions = 0x03,
        negative = false,
      }))
      local map = rbac.readable_entities_permissions({
        { id = role_id },
      })
      local res = map[entity_id].actions
      table.sort(res)
      assert.same({'create', 'read'}, res)
    end)
  end)
  describe("readable_endpoint_permissions", function()
    teardown(function()
      db:truncate()
    end)

    it("each action lala", function()
      local role_id = bp.rbac_roles:insert().id

      assert(db.rbac_role_endpoints:insert({
        role = { id = role_id },
        workspace = "foo",
        endpoint = "/bar",
        actions = 0x1,
        negative = false,
      }))
      local map = rbac.readable_endpoints_permissions({
        { id = role_id },
      })


      assert.same(rbac.readable_action(0x1), map.foo["/foo/bar"].actions[1])

      role_id = bp.rbac_roles:insert().id
      assert(db.rbac_role_endpoints:insert({
        role = { id = role_id },
        workspace = "foo",
        endpoint = "/bar",
        actions = 0x02,
        negative = false,
      }))
      local map = rbac.readable_endpoints_permissions({
        { id = role_id },
      })
      assert.equals(rbac.readable_action(0x2), map.foo["/foo/bar"].actions[1])

      role_id = bp.rbac_roles:insert().id
      assert(db.rbac_role_endpoints:insert({
        role = { id = role_id },
        workspace = "foo",
        endpoint = "/bar",
        actions = 0x04,
        negative = false,
      }))
      local map = rbac.readable_endpoints_permissions({
        { id = role_id },
      })
      assert.equals(rbac.readable_action(0x04), map.foo["/foo/bar"].actions[1])

      role_id = bp.rbac_roles:insert().id
      assert(db.rbac_role_endpoints:insert({
        role = { id = role_id },
        workspace = "foo",
        endpoint = "/bar",
        actions = 0x08,
        negative = false,
      }))
      local map = rbac.readable_endpoints_permissions({
        { id = role_id },
      })

      assert.equals(rbac.readable_action(0x08), map.foo["/foo/bar"].actions[1])
    end)
    it("multiple permission", function()
      local role_id = bp.rbac_roles:insert().id

      assert(db.rbac_role_endpoints:insert({
        role = { id = role_id },
        workspace = "foo",
        endpoint = "/bar",
        actions = 0x03,
        negative = false,
      }))
      local map = rbac.readable_endpoints_permissions({
        { id = role_id },
      })
      local res = map.foo["/foo/bar"].actions
      table.sort(res)
      assert.same({'create', 'read'}, res)
    end)
  end)

  describe("RbacRoleEndpoints", function()
    setup(function()
      db:truncate("rbac_role_endpoints")
    end)

    describe(":all_by_endpoint", function()
      it("returns the permissions for a given endpoint and workspace, and not the others", function()
        local role = bp.rbac_roles:insert()
        local p1 = kong.db.rbac_role_endpoints:insert({
          role = { id = role.id },
          workspace = "foo",
          actions = 0x01,
          endpoint = "/foo"
        })
        -- p2 should not appear, since endpoint is "/bar"
        kong.db.rbac_role_endpoints:insert({
          role = { id = role.id },
          workspace = "foo",
          actions = 0x01,
          endpoint = "/bar"
        })
        local res = kong.db.rbac_role_endpoints:all_by_endpoint("/foo", "foo")
        assert.same({ p1 }, res)
      end)
    end)
  end)
end)
end
