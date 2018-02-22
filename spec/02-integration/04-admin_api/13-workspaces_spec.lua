local dao_helpers = require "spec.02-integration.03-dao.helpers"
local DAOFactory  = require "kong.dao.factory"
local helpers     = require "spec.helpers"
local cjson       = require "cjson"
local utils       = require "kong.tools.utils"
local workspaces  = require "kong.workspaces"

dao_helpers.for_each_dao(function(kong_config)

describe("(#" .. kong_config.database .. ") Admin API workspaces", function()
  local client, dao

  setup(function()
    dao = assert(DAOFactory.new(kong_config))

    dao:truncate_tables()
    helpers.run_migrations(dao)
    assert(helpers.start_kong({
      database = kong_config.database
    }))

    client = assert(helpers.admin_client())
  end)

  teardown(function()
    if client then
      client:close()
    end

    dao:truncate_tables()

    helpers.stop_kong()
  end)

  describe("/workspaces", function()
    describe("POST", function()
      it("creates a new workspace", function()
        local res = assert(client:send {
          method = "POST",
          path   = "/workspaces",
          body   = {
            name = "foo",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.is_true(utils.is_valid_uuid(json.id))
        assert.equals("foo", json.name)
        assert.is_nil(json.comment)
      end)

      it("handles unique constraint conflicts", function()
        local res = assert(client:send {
          method = "POST",
          path   = "/workspaces",
          body   = {
            name = "foo",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        assert.res_status(409, res)
      end)
    end)

    describe("GET", function()
      setup(function()
        local res = assert(client:send {
          method = "POST",
          path   = "/workspaces",
          body   = {
            name = "bar",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        assert.res_status(201, res)
      end)

      it("retrieves a list of workspaces", function()
        local res = assert(client:send {
          method = "GET",
          path   = "/workspaces",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals(3, json.total)
        assert.equals(3, #json.data)
      end)
    end)
  end)

  describe("/workspaces/:workspace", function()
    describe("PATCH", function()
      it("updates an existing entity", function()
        local res = assert(client:send {
          method = "PATCH",
          path   = "/workspaces/foo",
          body   = {
            comment = "foo comment",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals("foo comment", json.comment)
      end)
    end)

    describe("GET", function()
      it("retrieves the default workspace", function()
        local res = assert(client:send {
          method = "GET",
          path = "/workspaces/" .. workspaces.DEFAULT_WORKSPACE,
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals(workspaces.DEFAULT_WORKSPACE, json.name)
      end)

      it("retrieves a single workspace", function()
        local res = assert(client:send {
          method = "GET",
          path   = "/workspaces/foo",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals("foo", json.name)
      end)

      it("sends the appropriate status on an invalid entity", function()
        local res = assert(client:send {
          method = "GET",
          path   = "/workspaces/baz",
        })

        assert.res_status(404, res)
      end)
    end)

    describe("DELETE", function()
      it("refuses to delete default workspace", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/workspaces/default",
        })

        assert.res_status(405, res)
      end)

      it("removes a workspace", function()
        local res = assert(client:send {
          method = "DELETE",
          path   = "/workspaces/bar",
        })

        assert.res_status(204, res)
      end)

      it("sends the appropriate status on an invalid entity", function()
        local res = assert(client:send {
          method = "DELETE",
          path   = "/workspaces/bar",
        })

        assert.res_status(404, res)
      end)
    end)
  end)

  describe("/workspaces/:workspace/entites", function()
    local uuid1, uuid2

    setup(function()
      -- yayyyyyyy determinism!
      uuid1, uuid2 = "182f2cc8-008e-11e8-ba89-0ed5f89f718b",
                     "182f2f2a-008e-11e8-ba89-0ed5f89f718b"

      local w = dao.workspaces:find_all({
        name = "foo",
      })
      w = w[1].id

      assert(dao.workspace_entities:insert({
        workspace_id = w,
        entity_id = uuid1,
        entity_type = "foo",
      }))
      assert(dao.workspace_entities:insert({
        workspace_id = w,
        entity_id = uuid2,
        entity_type = "foo",
      }))
    end)

    describe("GET", function()
      it("returns a list of entities associated with the default workspace", function()
        local res = assert(client:send{
          method = "GET",
          path = "/workspaces/default/entities",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals(2, #json.data)
      end)
      it("returns a list of entities associated with the workspace", function()
        local res = assert(client:send {
          method = "GET",
          path = "/workspaces/foo/entities",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        table.sort(json.data, function(a, b) return a.entity_id < b.entity_id end)

        assert.equals(2, json.total)
        assert.equals(2, #json.data)
        assert.equals(uuid1, json.data[1].entity_id)
        assert.equals(uuid2, json.data[2].entity_id)
      end)

      it("resolves entity relationships when specified", function()
        local res = assert(client:send {
          method = "GET",
          path = "/workspaces/foo/entities?resolve",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        table.sort(json)

        assert.equals(2, #json)
        assert.equals(uuid1, json[1])
        assert.equals(uuid2, json[2])
      end)
    end)

    describe("POST", function()
      describe("creates a new relationship", function()
        local entities = {}
        setup(function()
          local api1 = assert(dao.apis:insert {
            name = "api1",
            uris = "/uri",
            upstream_url = "http://upstream",
          })
          entities.apis = api1

          local plugin1 = assert(dao.plugins:insert {
            name = "key-auth",
            config = {}
          })
          entities.plugins = plugin1

          local workspace = assert(dao.workspaces:insert {
              name = "bar",
          })
          entities.workspaces = workspace
        end)
        it("with many entity types", function()
          for entity_type, entity in pairs(entities) do
            local res = assert(client:send {
              method = "POST",
              path = "/workspaces/foo/entities",
              body = {
                entities = entity.id,
              },
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(201, res)
            local json = cjson.decode(body)

            assert.equals(entity.id, json[1].entity_id)
            assert.equals(entity_type, json[1].entity_type)
          end
        end)
      end)

      describe("handles errors", function()
        it("on duplicate association", function()
          local res = assert(client:send {
            method = "POST",
            path = "/workspaces/foo/entities",
            body = {
              entities = "182f2cc8-008e-11e8-ba89-0ed5f89f718b",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          local body = assert.res_status(409, res)
          local json = cjson.decode(body)

          assert.matches("Entity '182f2cc8-008e-11e8-ba89-0ed5f89f718b' " ..
                         "already associated with workspace", json.message, nil,
                         true)
        end)

        it("on invalid UUID", function()
          local res = assert(client:send {
            method = "POST",
            path = "/workspaces/foo/entities",
            body = {
              entities = "nop",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.equals("'nop' is not a valid UUID", json.message)
        end)

        it("on circular reference", function()
          local bar_id = dao.workspaces:find_all({
            name = "bar",
          })[1].id
          local foo_id = dao.workspaces:find_all({
            name = "foo",
          })[1].id

          local res = assert(client:send {
            method = "POST",
            path = "/workspaces/bar/entities",
            body = {
              entities = foo_id,
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local body = assert.res_status(409, res)
          local json = cjson.decode(body)

          assert.equals("Attempted to create circular reference " ..
                        "(workspace '" .. foo_id .. "' already references " ..
                        "'" .. bar_id .. "')", json.message)
        end)

        it("without inserting some valid rows prior to failure", function()
          local n = dao.workspace_entities:find_all({
            workspace_id = dao.workspaces:find_all({ name = "foo" })[1].id
          })
          n = #n

          local res = assert(client:send {
            method = "POST",
            path = "/workspaces/foo/entities",
            body = {
              entities = utils.uuid() .. ",nop",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.equals("'nop' is not a valid UUID", json.message)

          local new_n = dao.workspace_entities:find_all({
            workspace_id = dao.workspaces:find_all({ name = "foo" })[1].id
          })
          new_n = #new_n
          assert.same(n, new_n)
        end)
      end)
    end)

    describe("DELETE", function()
      it("removes a relationship", function()
        local n = dao.workspace_entities:find_all({
          workspace_id = dao.workspaces:find_all({ name = "foo" })[1].id
        })
        n = #n

        local res = assert(client:send {
          method = "DELETE",
          path = "/workspaces/foo/entities",
          body = {
            entities = "182f2cc8-008e-11e8-ba89-0ed5f89f718b",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        assert.res_status(204, res)

        local new_n = dao.workspace_entities:find_all({
          workspace_id = dao.workspaces:find_all({ name = "foo" })[1].id
        })
        new_n = #new_n
        assert.equals(n - 1, new_n)
      end)

      it("sends the appropriate status on an invalid entity", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/workspaces/baz/entities",
          body = {
            entities = utils.uuid(),
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        assert.res_status(404, res)
      end)
    end)
  end)

  describe("/workspaces/:workspace/entites/:entity", function()
    local w_id, e_id

    setup(function()
      w_id = dao.workspaces:find_all({ name = "foo" })[1].id
      e_id = utils.uuid()

      assert(dao.workspace_entities:insert({
        workspace_id = w_id,
        entity_id = e_id,
        entity_type = "foo",
      }))
    end)

    describe("GET", function()
      it("returns a single relation representation", function()
        local res = assert(client:send {
          method = "GET",
          path = "/workspaces/foo/entities/" .. e_id,
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals(json.workspace_id, w_id)
        assert.equals(json.entity_id, e_id)
        assert.equals(json.entity_type, "foo")
      end)

      it("sends the appropriate status on an invalid entity", function()
        local res = assert(client:send {
          method = "GET",
          path = "/workspaces/foo/entities/" .. utils.uuid(),
        })

        assert.res_status(404, res)
      end)
    end)

    describe("DELETE", function()
      it("removes a single relation representation", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/workspaces/foo/entities/" .. e_id,
        })

        assert.res_status(204, res)
      end)

      it("sends the appropriate status on an invalid entity", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/workspaces/foo/entities/" .. utils.uuid(),
        })

        assert.res_status(404, res)
      end)
    end)
  end)
end)

end)
