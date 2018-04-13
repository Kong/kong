local helpers     = require "spec.helpers"
local dao_factory = require "kong.dao.factory"
local dao_helpers = require "spec.02-integration.03-dao.helpers"
local utils       = require "kong.tools.utils"
local singletons  = require "kong.singletons"


local rbac


local MAX_ITERATIONS = 12


dao_helpers.for_each_dao(function(kong_conf)
describe("(#" .. kong_conf.database .. ")", function()
  local dao


  setup(function()
    package.loaded["kong.rbac"] = nil

    dao = assert(dao_factory.new(kong_conf))
    singletons.dao = dao
    rbac = require "kong.rbac"
  end)


  describe("RBAC", function()
    local iterations
    setup(function()
      math.randomseed(ngx.now())
      iterations = math.random(4, MAX_ITERATIONS)


      helpers.run_migrations(dao)
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
            assert(dao.workspace_entities:insert({
              workspace_id = workspace,
              entity_id = entity,
              entity_type = "entity",
            }))
          end
        end
      end)

      teardown(function()
        dao:truncate_tables()
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
          assert(dao.workspace_entities:insert({
            workspace_id = workspaces[#workspaces],
            entity_id = workspaces[x],
            entity_type = "workspaces",
          }))

          -- add another workspace, associated with an existing workspace,
          -- and containing its own entities as well
          workspaces[#workspaces + 1] = u()
          assert(dao.workspace_entities:insert({
            workspace_id = workspaces[#workspaces],
            entity_id = workspaces[x],
            entity_type = "workspaces",
          }))

          entities[#workspaces] = {}
          for i = 1, math.random(10) do
            table.insert(entities[#workspaces], u())
            assert(dao.workspace_entities:insert({
              workspace_id = workspaces[#workspaces],
              entity_id = entities[#workspaces][i],
              entity_type = "entity",
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
            assert(dao.workspace_entities:insert({
              workspace_id = workspaces[#workspaces],
              entity_id = workspaces[#workspaces - 1],
              entity_type = "workspace",
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

          assert(dao.workspace_entities:insert({
            workspace_id = x,
            entity_id = y,
            entity_type = "workspace"
          }))
          assert(dao.workspace_entities:insert({
            workspace_id = y,
            entity_id = x,
            entity_type = "workspace"
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
        role_id = u()
        entity_id = u()

        assert(dao.role_entities:insert({
          role_id = role_id,
          entity_id = entity_id,
          entity_type = "entity",
          actions = 0x1,
          negative = false,
        }))
      end)

      teardown(function()
        dao:truncate_tables()
      end)

      it("returns a map given a role", function()
        local map = rbac.resolve_role_entity_permissions({
          { id = role_id },
        })

        assert.equals(0x1, map[entity_id])
      end)

      describe("prioritizes explicit negative permissions", function()
        local role_id2 = utils.uuid()

        setup(function()
          assert(dao.role_entities:insert({
            role_id = role_id2,
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

          assert.equals(0x0, map[entity_id])
        end)

        it("regardless of role order", function()
          local map = rbac.resolve_role_entity_permissions({
            { id = role_id2 },
            { id = role_id },
          })

          assert.equals(0x0, map[entity_id])
        end)
      end)

      describe("loads workspace entities", function()
        local roles, workspaces, entities = {}, {}, {}

        setup(function()
          local u = utils.uuid
          for i = 1, 2 do
            roles[i] = u()
            workspaces[i] = u()
            entities[i] = u()
          end


          -- clear the existing role->entity mappings
          helpers.run_migrations()


          -- create a workspace with some entities
          assert(dao.workspace_entities:insert({
            workspace_id = workspaces[1],
            entity_id = entities[1],
            entity_type = "entity",
          }))

          -- create a workspace pointing to another workspace, and
          -- containing its own entities
          assert(dao.workspace_entities:insert({
            workspace_id = workspaces[2],
            entity_id = workspaces[1],
            entity_type = "workspace",
          }))
          assert(dao.workspace_entities:insert({
            workspace_id = workspaces[2],
            entity_id = entities[2],
            entity_type = "entity",
          }))

          -- assign two roles; the first role to the first workspace
          -- (which owns entities[1]), and the second role to the second
          -- workspace (which owns workspaces[1] and entities[2])
          assert(dao.role_entities:insert({
            role_id = roles[1],
            entity_id = workspaces[1],
            entity_type = "workspace",
            actions = 0x1,
            negative = false,
          }))
          assert(dao.role_entities:insert({
            role_id = roles[2],
            entity_id = workspaces[2],
            entity_type = "workspace",
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
        local u = utils.uuid

        table.insert(role_ids, u())
        assert(dao.role_endpoints:insert({
          role_id = role_ids[#role_ids],
          workspace = "foo",
          endpoint = "bar",
          actions = 0x1,
          negative = false,
        }))

        table.insert(role_ids, u())
        assert(dao.role_endpoints:insert({
          role_id = role_ids[#role_ids],
          workspace = "foo",
          endpoint = "bar",
          actions = 0x1,
          negative = true,
        }))

        assert(dao.role_endpoints:insert({
          role_id = role_ids[#role_ids],
          workspace = "baz",
          endpoint = "bar",
          actions = 0x5,
          negative = false,
        }))
      end)

      teardown(function()
        dao:truncate_tables()
      end)

      it("returns a permissions map for a given role", function()
        local map = rbac.resolve_role_endpoint_permissions({
          { id = role_ids[1] },
        })

        assert.equals(0x1, map.foo.bar)
      end)

      it("returns a permissions map for multiple roles", function()
        local map = rbac.resolve_role_endpoint_permissions({
          { id = role_ids[1] },
          { id = role_ids[2] },
        })

        assert.equals(0x11, map.foo.bar)
      end)

      it("returns separate permissions under separate workspaces", function()
        local map = rbac.resolve_role_endpoint_permissions({
          { id = role_ids[2] },
        })

        assert.equals(0x10, map.foo.bar)
        assert.equals(0x5, map.baz.bar)
      end)
    end)
  end)

  describe(".authorize_request_endpoint", function()
    describe("authorizes a request", function()
      describe("workspace/endpoint", function()
        it("(positive)", function()
          assert.equals(true, rbac.authorize_request_endpoint(
            { foo = { bar = 0x1 } },
            "foo",
            "bar",
            rbac.actions_bitfields.read
          ))
        end)

        it("(negative override)", function()
          assert.equals(false, rbac.authorize_request_endpoint(
            { foo = { bar = 0x11 } },
            "foo",
            "bar",
            rbac.actions_bitfields.read
          ))
        end)
        it("(empty)", function()
          assert.equals(false, rbac.authorize_request_endpoint(
            { foo = { baz = 0x1 } },
            "foo",
            "bar",
            rbac.actions_bitfields.read
          ))
        end)
      end)
      describe("workspace/*", function()
        it("(positive)", function()
          assert.equals(true, rbac.authorize_request_endpoint(
            { foo = { ["*"] = 0x1 } },
            "foo",
            "bar",
            rbac.actions_bitfields.read
          ))
        end)
        it("(negative)", function()
          assert.equals(false, rbac.authorize_request_endpoint(
            { foo = { ["*"] = 0x11 } },
            "foo",
            "bar",
            rbac.actions_bitfields.read
          ))
        end)
        it("does not override specific endpoint", function()
          assert.equals(true, rbac.authorize_request_endpoint(
            { foo = { ["*"] = 0x11, bar = 0x1 } },
            "foo",
            "bar",
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
            rbac.actions_bitfields.read
          ))
        end)
        it("(negative)", function()
          assert.equals(false, rbac.authorize_request_endpoint(
            { ["*"] = { bar = 0x11 } },
            "foo",
            "bar",
            rbac.actions_bitfields.read
          ))
        end)
        it("(empty(", function()
          assert.equals(true, rbac.authorize_request_endpoint(
            { ["*"] = { bar = 0x1 } },
            "baz",
            "bar",
            rbac.actions_bitfields.read
          ))
        end)
        it("does not override specific workspace", function()
          assert.equals(true, rbac.authorize_request_endpoint(
            { foo = { ["*"] = 0x11, bar = 0x1 }, ["*"] = { bar = 0x1 } },
            "foo",
            "bar",
            rbac.actions_bitfields.read
          ))
          assert.equals(false, rbac.authorize_request_endpoint(
            { foo = { ["*"] = 0x11, bar = 0x1 }, ["*"] = { bar = 0x1 } },
            "foo",
            "baz",
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
            rbac.actions_bitfields.read
          ))
        end)
        it("(negative)", function()
          assert.equals(false, rbac.authorize_request_endpoint(
            { ["*"] = { ["*"] = 0x11 } },
            "foo",
            "bar",
            rbac.actions_bitfields.read
          ))
        end)
        it("does not override a specific workspace/endpoint", function()
          assert.equals(false, rbac.authorize_request_endpoint(
            { ["*"] = { ["*"] = 0x1 }, foo = { bar = 0x11 } },
            "foo",
            "bar",
            rbac.actions_bitfields.read
          ))
          assert.equals(true, rbac.authorize_request_endpoint(
            { ["*"] = { ["*"] = 0x1 }, foo = { bar = 0x11 } },
            "baz",
            "bar",
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
          rbac.actions_bitfields.read
        ))
        assert.equals(false, rbac.authorize_request_endpoint(
          { foo = { bar = 0x1 } },
          "foo",
          "bar",
          rbac.actions_bitfields.create
        ))
        assert.equals(true, rbac.authorize_request_endpoint(
          { foo = { bar = 0x3 } },
          "foo",
          "bar",
          rbac.actions_bitfields.create
        ))
      end)
      it("given permissive and denial bits", function()
        assert.equals(false, rbac.authorize_request_endpoint(
          { foo = { bar = 0x12 } },
          "foo",
          "bar",
          rbac.actions_bitfields.read
        ))
        assert.equals(true, rbac.authorize_request_endpoint(
          { foo = { bar = 0x12 } },
          "foo",
          "bar",
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

end)
end)
