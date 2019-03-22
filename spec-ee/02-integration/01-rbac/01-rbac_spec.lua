local spec_helpers = require "spec.helpers"
local dao_helpers = require "spec.02-integration.03-dao.helpers"
local utils       = require "kong.tools.utils"
local singletons  = require "kong.singletons"
local bit = require "bit"


local rbac


local MAX_ITERATIONS = 12


dao_helpers.for_each_dao(function(kong_conf)
describe("(#" .. kong_conf.database .. ")", function()
  local dao, db, bp


  setup(function()
    package.loaded["kong.rbac"] = nil

    bp, db, dao = spec_helpers.get_db_utils()
    singletons.dao = dao
    singletons.db = db

    rbac = require "kong.rbac"
  end)


  describe("RBAC", function()
    local iterations
    setup(function()
      math.randomseed(ngx.now())
      iterations = math.random(4, MAX_ITERATIONS)
    end)

    describe(".bitfield_all_actions", function()
      local all_actions = rbac.bitfield_all_actions
      for perm_name, perm_bit in pairs(rbac.actions_bitfields) do
        it("has '" .. perm_name .. "' permissions", function()
          assert.equals(perm_bit, bit.band(perm_bit, all_actions))
        end)
      end
    end)

    describe(".resolve_workspace_entities", function()
      local workspaces, entities = {}, {}

      setup(function()
        -- create a random number of workspaces, each with a random number
        -- of distinct entities. in these intial workspaces there are no
        -- cross-references; we test that in a separate block below
        local u = utils.uuid
        for i = 1, iterations do
          table.insert(workspaces, u())

          entities[i] = {}
          for j = 1, math.random(MAX_ITERATIONS) do
            table.insert(entities[i], u())
          end
        end

        for i, workspace in ipairs(workspaces) do
          for j, entity in ipairs(entities[i]) do
            assert(db.workspace_entities:insert({
              workspace_id = workspace,
              workspace_name = "ws_name",
              entity_id = entity,
              entity_type = "entity",
              unique_field_name="id",
              unique_field_value=entity,
            }))
          end
        end
      end)

      teardown(function()
        db:truncate()
      end)

      it("returns entities for a given workspace id", function()
        for i = 1, #workspaces do
          local ws_entities = rbac.resolve_workspace_entities({workspaces[i]})

          assert.equals(#entities[i], #ws_entities)
          for _, ws in ipairs(entities[i]) do
            assert.equals(true, ws_entities[ws])
          end
        end
      end)

      it("returns entities given multiple workspaces", function()
        -- load a random workspace, and the next defined workspace
        -- using a small bit of math to avoid overruns
        local x = math.max(1, math.random(#workspaces - 1))
        local y = x + 1

        local ws_entities = rbac.resolve_workspace_entities({
          workspaces[x],
          workspaces[y],
        })

        assert.equals(#entities[x] + #entities[y], #ws_entities)
        for _, ws in ipairs(entities[x]) do
          assert.equals(true, ws_entities[ws])
        end
        for _, ws in ipairs(entities[y]) do
          assert.equals(true, ws_entities[ws])
        end
      end)

      describe("recurses", function()
        -- pointer to a random workspace with which we will associate
        -- a new workspace, to recursively load its entities
        local x = math.random(#workspaces)

        setup(function()
          local u = utils.uuid

          -- add another workspace, associated with an existing workspace
          workspaces[#workspaces + 1] = u()
          assert(db.workspace_entities:insert({
            workspace_id = workspaces[#workspaces],
            workspace_name = "ws_name",
            entity_id = workspaces[x],
            entity_type = "workspaces",
            unique_field_name="id",
            unique_field_value=workspaces[x],
          }))

          -- add another workspace, associated with an existing workspace,
          -- and containing its own entities as well
          workspaces[#workspaces + 1] = u()
          assert(db.workspace_entities:insert({
            workspace_id = workspaces[#workspaces],
            workspace_name = "ws_name",
            entity_id = workspaces[x],
            entity_type = "workspaces",
            unique_field_name="id",
            unique_field_value=workspaces[x],
          }))

          entities[#workspaces] = {}
          for i = 1, math.random(10) do
            table.insert(entities[#workspaces], u())
            assert(db.workspace_entities:insert({
              workspace_id = workspaces[#workspaces],
              workspace_name = "ws_name",
              entity_id = entities[#workspaces][i],
              entity_type = "entity",
              unique_field_name="id",
              unique_field_value=entities[#workspaces][i],
            }))
          end
        end)

        it("given a single workspace association", function()
          -- #workspaces - 1 is the second-to-last workspace;
          -- its only entity is another workspace
          local ws_entities = rbac.resolve_workspace_entities({
            workspaces[#workspaces - 1]
          })

          assert.equals(#entities[x], #ws_entities)

          for _, ws in ipairs(entities[x]) do
            assert.equals(true, ws_entities[ws])
          end
        end)

        it("with additional entities", function()
          local ws_entities = rbac.resolve_workspace_entities({
            workspaces[#workspaces]
          })

          -- search for the entities in our cross referenced workspaces,
          -- and for the entities in the final workspace we created in this
          -- block's setup()
          assert.equals(#entities[#workspaces] + #entities[x], #ws_entities)
          for _, ws in ipairs(entities[x]) do
            assert.equals(true, ws_entities[ws])
          end
          for _, ws in ipairs(entities[#workspaces]) do
            assert.equals(true, ws_entities[ws])
          end
        end)

        describe("with multiple levels of nesting", function()
          -- define a workspace associated with another workspace,
          -- itself having its own entities and a relationship with
          -- a third workspace containing a separate set of entities
          -- this, the resolved list of entities of this new workspace
          -- is the union of the the workspace's parent and grandparent
          setup(function()
            workspaces[#workspaces + 1] = utils.uuid()
            assert(db.workspace_entities:insert({
              workspace_id = workspaces[#workspaces],
              workspace_name = "ws_name",
              entity_id = workspaces[#workspaces - 1],
              entity_type = "workspaces",
              unique_field_name="id",
              unique_field_value=workspaces[#workspaces - 1],
            }))
          end)

          it("", function()
            local ws_entities = rbac.resolve_workspace_entities({
              workspaces[#workspaces]
            })

            assert.equals(#entities[#workspaces - 1] + #entities[x],
                          #ws_entities)
            for _, ws in ipairs(entities[x]) do
              assert.equals(true, ws_entities[ws])
            end
            for _, ws in ipairs(entities[#workspaces - 1]) do
              assert.equals(true, ws_entities[ws])
            end
          end)
        end)
      end)

      describe("does not tolerate circular references", function()
        local x

        setup(function()
          local y
          x, y = utils.uuid(), utils.uuid()

          assert(db.workspace_entities:insert({
            workspace_id = x,
            workspace_name = "ws_name",
            entity_id = y,
            entity_type = "workspaces",
            unique_field_name="id",
            unique_field_value=y,
          }))
          assert(db.workspace_entities:insert({
            workspace_id = y,
            workspace_name = "ws_name",
            entity_id = x,
            entity_type = "workspaces",
            unique_field_name="id",
            unique_field_value=x,
          }))
        end)

        it("", function()
          local e = function()
            rbac.resolve_workspace_entities({ x })
          end

          assert.has_error(e, "already seen workspace " .. x)
        end)
      end)
    end)

    describe(".resolve_role_entity_permissions", function()
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
        local map = rbac.resolve_role_entity_permissions({
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
          local map = rbac.resolve_role_entity_permissions({
            { id = role_id },
            { id = role_id2 },
          })

          -- role_id  has 1 positive read (1) permission
          -- role_id2 has 1 negative read (1 << 4) permission
          -- (1 | 1 << 4) == 17
          assert.equals(17, map[entity_id])
        end)

        it("regardless of role order", function()
          local map = rbac.resolve_role_entity_permissions({
            { id = role_id2 },
            { id = role_id },
          })

          -- role_id  has 1 positive read (1) permission
          -- role_id2 has 1 negative read (1 << 4) permission
          -- (1 | 1 << 4) == 17
          assert.equals(17, map[entity_id])
        end)
      end)

      describe("loads workspace entities", function()
        local roles, workspaces, entities = {}, {}, {}

        setup(function()
          local u = utils.uuid
          for i = 1, 2 do
            roles[i] = bp.rbac_roles:insert().id
            workspaces[i] = u()
            entities[i] = u()
          end


          -- clear the existing role->entity mappings
          dao:run_migrations()


          -- create a workspace with some entities
          assert(db.workspace_entities:insert({
            workspace_id = workspaces[1],
            workspace_name = "ws_name",
            entity_id = entities[1],
            entity_type = "entity",
            unique_field_name="id",
            unique_field_value=entities[1],
          }))

          -- create a workspace pointing to another workspace, and
          -- containing its own entities
          assert(db.workspace_entities:insert({
            workspace_id = workspaces[2],
            workspace_name = "ws_name",
            entity_id = workspaces[1],
            entity_type = "workspaces",
            unique_field_name="id",
            unique_field_value=workspaces[1],
          }))
          assert(db.workspace_entities:insert({
            workspace_id = workspaces[2],
            workspace_name = "ws_name",
            entity_id = entities[2],
            entity_type = "entity",
            unique_field_name="id",
            unique_field_value=entities[2],
          }))

          -- assign two roles; the first role to the first workspace
          -- (which owns entities[1]), and the second role to the second
          -- workspace (which owns workspaces[1] and entities[2])
          assert(db.rbac_role_entities:insert({
            role = { id = roles[1] },
            entity_id = workspaces[1],
            entity_type = "workspaces",
            actions = 0x1,
            negative = false,
          }))
          assert(db.rbac_role_entities:insert({
            role = {id = roles[2] },
            entity_id = workspaces[2],
            entity_type = "workspaces",
            actions = 0x1,
            negative = false,
          }))
        end)

        it("for a given role", function()
          local map = rbac.resolve_role_entity_permissions({
            { id = roles[1] },
          })

          assert.equals(0x1, map[entities[1]])
          assert.is_nil(map[entities[2]])

          map = rbac.resolve_role_entity_permissions({
            { id = roles[2] },
          })

          assert.equals(0x1, map[entities[1]])
          assert.equals(0x1, map[entities[2]])
        end)

        it("for multiple roles", function()
          local map = rbac.resolve_role_entity_permissions({
            { id = roles[1] },
            { id = roles[2] },
          })

          assert.equals(0x1, map[entities[1]])
          assert.equals(0x1, map[entities[2]])
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
  describe(".authorize_request_entity", function()
    it("returns true on bit match", function()
      assert.equals(true, rbac.authorize_request_entity(
        { foo = 0x1 },
        "foo",
        0x1
      ))
    end)

    it("returns true when multiple bits are assigned", function()
      for i = 1, 4 do
        assert.equals(true, rbac.authorize_request_entity(
          { foo = 0xf },
          "foo",
          (2 ^ i) - 1
        ))
      end
    end)

    it("returns false when no bit is unset", function()
      assert.equals(false, rbac.authorize_request_entity(
        { foo = 0x1 },
        "foo",
        0x2
      ))
    end)

    it("returns false when no key is present", function()
      assert.equals(false, rbac.authorize_request_entity(
        { foo = 0x1 },
        "bar",
        0x1
      ))
      assert.equals(false, rbac.authorize_request_entity(
        {},
        "bar",
        0x1
      ))
    end)
  end)
  describe("check_cascade", function()
    local entities
    setup(function()
      local singletons = require "kong.singletons"
      singletons.configuration= {
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
      singletons.configuration = nil
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
      singletons.configuration= {
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
end)
end)
