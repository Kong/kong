local helpers     = require "spec.helpers"
local cjson       = require "cjson"
local utils       = require "kong.tools.utils"
local workspaces  = require "kong.workspaces"


for _, strategy in helpers.each_strategy() do

describe("Workspaces Admin API (#" .. strategy .. "): ", function()
  local client, dao, db, bp

  setup(function()
    bp, db, dao = helpers.get_db_utils(strategy)

    assert(helpers.start_kong({
      database = strategy,
    }))

    client = assert(helpers.admin_client())
  end)

  before_each(function()
    db:truncate("workspaces")
    db:truncate("workspace_entities")
  end)

  teardown(function()
    if client then
      client:close()
    end

    helpers.stop_kong()
  end)

  describe("/workspaces", function()
    describe("POST", function()
      it("creates a new workspace", function()
        local res = assert(client:post("/workspaces", {
          body   = {
            name = "foo",
            meta = {
              color = "#92b6d5"
            }
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.is_true(utils.is_valid_uuid(json.id))
        assert.equals("foo", json.name)

        -- no files created, portal is off
        local files_count = dao.files:count()
        assert.equals(0, files_count)
      end)

      it("handles empty workspace name passed on creation", function()
        local res = assert(client:post("/workspaces", {
          body = {},
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)

        assert.equals("required field missing", json.fields.name)
      end)

      it("handles unique constraint conflicts", function()
        bp.workspaces:insert({
          name = "foo",
        })
        local res = assert(client:post("/workspaces", {
          body   = {
            name = "foo",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
        assert.res_status(409, res)
      end)

      it("handles invalid meta json", function()
        local res = assert(client:post("/workspaces", {
          body   = {
            name = "foo",
            meta = "{ color: red }" -- invalid json
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)

        assert.equals("expected a record", json.fields.meta)
      end)

      it("creates default files if portal is ON", function()
        local res = assert(client:post("/workspaces", {
          body   = {
            name = "ws-with-portal",
            config = {
              portal = true
            }
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.is_true(utils.is_valid_uuid(json.id))
        assert.equals("ws-with-portal", json.name)

        local res = assert(client:get("/ws-with-portal/files"))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.truthy(#json.data > 0)
      end)
    end)

    describe("GET", function()
      it("retrieves a list of workspaces", function()
        local num_to_create = 4
        assert(bp.workspaces:insert_n(num_to_create))

        local res = assert(client:send {
          method = "GET",
          path   = "/workspaces",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        -- total is number created + default
        assert.equals(num_to_create + 1, #json.data)
      end)

      it("returns 404 if called from other than default workspace", function()
        assert.res_status(404, client:get("/bar/workspaces"))
        assert.res_status(200, client:get("/default/workspaces"))
      end)
    end)
  end)

  describe("/workspaces/:workspace", function()
    describe("PATCH", function()
      it("refuses to update the workspace name", function()
        assert(bp.workspaces:insert {
          name = "foo",
          meta = {
            color = "red",
          }
        })

        local res = assert(client:patch("/workspaces/foo", {
          body = {
            name = "new_foo",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        }))

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)

        assert.equals("Cannot rename a workspace", json.message)
      end)

      it("updates an existing entity", function()
        assert(bp.workspaces:insert {
          name = "foo",
        })

        local res = assert(client:patch("/workspaces/foo", {
          body   = {
            comment = "foo comment",
            meta = {
              color = "red",
              thumbnail = "cool"
            }
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals("foo comment", json.comment)
        assert.equals("red", json.meta.color)
      end)

      it("creates default files if portal is turned on", function()
        assert(bp.workspaces:insert {
          name = "rad-portal-man",
        })

        -- patch to enable portal
        assert.res_status(200, client:patch("/workspaces/rad-portal-man", {
          body   = {
            config = {
              portal = true
            }
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))

        -- make sure /files exists
        local res = assert(client:get("/rad-portal-man/files"))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.truthy(#json.data > 0)
      end)

      it("respects previoulsy set config values on update", function()
        assert(bp.workspaces:insert {
          name = "sweet-portal-dude",
          config = {
            portal = true,
            portal_auth = "basic-auth",
            portal_auto_approve = true,
          }
        })

        -- patch to update workspace config
        assert.res_status(200, client:patch("/workspaces/sweet-portal-dude", {
          body   = {
            config = {
              portal_auth = "key-auth"
            }
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))

        local expected_config = {
          portal = true,
          portal_auth = "key-auth",
          portal_auto_approve = true,
        }

        local res = assert(client:get("/workspaces/sweet-portal-dude"))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equals(json.config.portal, expected_config.portal)
        assert.equals(json.config.portal_auth, expected_config.portal_auth)
        assert.equals(json.config.portal_auto_approve, expected_config.portal_auto_approve)
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
        assert(bp.workspaces:insert {
          name = "foo",
          meta = {
            color = "red",
          }
        })

        local res = assert(client:get("/workspaces/foo"))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals("foo", json.name)
        assert.equals("red", json.meta.color)
      end)

      it("sends the appropriate status on an invalid entity", function()
        assert.res_status(404, client:get("/workspaces/baz"))
      end)

      it("returns 404 if we call from another workspace", function()
        assert(bp.workspaces:insert {
          name = "foo",
        })
        assert.res_status(404, client:get("/foo/workspaces/default"))
        assert.res_status(200, client:get("/workspaces/foo"))
        assert.res_status(200, client:get("/default/workspaces/foo"))
        assert.res_status(200, client:get("/foo/workspaces/foo"))
      end)
    end)

    describe("delete", function()
      it("refuses to delete default workspace", function()
        assert.res_status(400, client:delete("/workspaces/default"))
      end)

      it("removes a workspace", function()
        assert(bp.workspaces:insert {
          name = "bar",
        })
        assert.res_status(204, client:delete("/workspaces/bar"))
      end)

      it("sends the appropriate status on an invalid entity", function()
        assert.res_status(404, client:delete("/workspaces/bar"))
      end)

      it("refuses to delete a non empty workspace", function()
        local ws = assert(bp.workspaces:insert {
          name = "foo",
        })
        bp.services:insert_ws({}, ws)

        local res = assert(client:send {
          method = "delete",
          path   = "/workspaces/foo",
        })
        assert.res_status(400, res)
      end)
    end)
  end)

  describe("/workspaces/:workspace/entites", function()
    describe("GET", function()
      it("returns a list of entities associated with the default workspace", function()
        local res = assert(client:send{
          method = "GET",
          path = "/workspaces/default/entities",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        -- no entity associated with it by default
        -- previously, when workspaces were workspaceable, the count was 2,
        -- given default was in default, and each entity adds two rows in
        -- workspace_entities
        assert.equals(0, #json.data)
      end)

      it("returns a list of entities associated with the workspace", function()
        assert(bp.workspaces:insert {
          name = "foo"
        })
        -- create some entities
        local consumers = bp.consumers:insert_n(10)

        -- share them
        for _, consumer in ipairs(consumers) do
          assert.res_status(201, client:post("/workspaces/foo/entities", {
            body = {
              entities = consumer.id
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          }))
        end

        local res = assert(client:send {
          method = "GET",
          path = "/workspaces/foo/entities",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert(10, #json.data)
        for _, entity in ipairs(json.data) do
          assert.same("consumers", entity.entity_type)
        end
      end)
    end)

    describe("POST", function()
      describe("handles errors", function()
        it("on duplicate association", function()
          assert(bp.workspaces:insert {
            name = "foo"
          })
          local consumer = assert(bp.consumers:insert())

          local res = assert(client:post("/workspaces/foo/entities", {
            body = {
              entities = consumer.id,
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          }))
          assert.res_status(201, res)

          local res = assert(client:post("/workspaces/foo/entities", {
            body = {
              entities = consumer.id,
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          }))
          local json = cjson.decode(assert.res_status(409, res))
          assert.matches("Entity '" .. consumer.id .. "' " ..
                         "already associated with workspace", json.message, nil,
                         true)
        end)

        it("on invalid UUID", function()
          assert(bp.workspaces:insert {
            name = "foo"
          })

          local res = assert(client:post("/workspaces/foo/entities", {
            body = {
              entities = "nop",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          }))

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.equals("'nop' is not a valid UUID", json.message)
        end)

        it("without inserting some valid rows prior to failure", function()
          local ws = assert(bp.workspaces:insert {
            name = "foo"
          })

          local n = db.workspace_entities:select_all({
            workspace_id = ws.id
          })
          n = #n

          local res = assert(client:post("/workspaces/foo/entities", {
            body = {
              entities = utils.uuid() .. ",nop",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          }))

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.equals("'nop' is not a valid UUID", json.message)

          local new_n = db.workspace_entities:select_all({
            workspace_id = ws.id
          })
          new_n = #new_n
          assert.same(n, new_n)
        end)
      end)
    end)

    describe("DELETE", function()
      it("fails to remove an unexisting entity relationship", function()
        assert.res_status(404, client:send {
          method = "DELETE",
          path = "/workspaces/foo/entities",
          body = {
            entities = utils.uuid()
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
      end)

      it("does not leave dangling entities (old dao)", function()
        -- create a workspace
        assert(bp.workspaces:insert({
          name = "foo",
        }))
        -- create a consumer
        local consumer = assert(bp.consumers:insert())

        -- share with workspace foo
        assert.res_status(201, client:post("/workspaces/foo/entities", {
          body = {
            entities = consumer.id
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        }))

        -- now, delete the entity from foo
        assert.res_status(204, client:delete("/workspaces/foo/entities", {
          body = {
            entities = consumer.id
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        }))

        -- and delete it from default, too
        assert.res_status(204, client:delete("/workspaces/default/entities", {
          body = {
            entities = consumer.id
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        }))

        -- the entity must be gone - as it was deleted from both workspaces
        -- it belonged to
        local res, err = db.consumers:select({
          id = consumer.id
        })
        assert.is_nil(err)
        assert.is_nil(res)

        -- and we must be able to create an entity with that same name again
        assert.res_status(201, client:send {
          method = "POST",
          path = "/consumers",
          body = {
            username = "foosumer"
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
      end)

      it("removes a relationship", function()
        -- create a workspace
        assert(bp.workspaces:insert({
          name = "foo",
        }))
        -- create a consumer
        local consumer = assert(bp.consumers:insert())

        -- share with workspace foo
        assert.res_status(201, client:post("/workspaces/foo/entities", {
          body = {
            entities = consumer.id
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        }))

        -- now, delete the entity from foo
        assert.res_status(204, client:send {
          method = "DELETE",
          path = "/workspaces/foo/entities",
          body = {
            entities = consumer.id
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        -- now, delete the entity from foo
        local json = cjson.decode(assert.res_status(200, client:get("/workspaces/foo/entities", {
          body = {
            entities = consumer.id
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })))

        assert.truthy(#json.data == 0)
      end)

      it("sends the appropriate status on an invalid entity", function()
        assert(bp.workspaces:insert({
          name = "foo",
        }))
        assert.res_status(404, client:delete("/workspaces/foo/entities", {
          body = {
            entities = utils.uuid(),
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        }))
      end)
    end)
  end)

  describe("/workspaces/:workspace/entites/:entity", function()
    describe("GET", function()
      it("returns a single relation representation", function()
        -- create a workspace
        local ws = assert(bp.workspaces:insert({
          name = "foo",
        }))
        -- create a consumer
        local consumer = assert(bp.consumers:insert_ws(nil, ws))

        local res = assert(client:send {
          method = "GET",
          path = "/workspaces/foo/entities/" .. consumer.id,
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals(json.workspace_id, ws.id)
        assert.equals(json.entity_id, consumer.id)
        assert.equals(json.entity_type, "consumers")
      end)

      it("sends the appropriate status on an invalid entity", function()
        -- create a workspace
        assert(bp.workspaces:insert({
          name = "foo",
        }))

        assert.res_status(404, client:send {
          method = "GET",
          path = "/workspaces/foo/entities/" .. utils.uuid(),
        })
      end)
    end)

    describe("DELETE", function()
      it("removes a single relation representation", function()
        -- create a workspace
        local ws = assert(bp.workspaces:insert({
          name = "foo",
        }))
        -- create a consumer
        local consumer = assert(bp.consumers:insert_ws(nil, ws))

        assert.res_status(204, client:send({
          method = "DELETE",
          path = "/workspaces/foo/entities/" .. consumer.id,
        }))
      end)

      it("sends the appropriate status on an invalid entity", function()
        assert(bp.workspaces:insert({
          name = "foo",
        }))
        assert.res_status(404, client:send {
          method = "DELETE",
          path = "/workspaces/foo/entities/" .. utils.uuid(),
        })
      end)
    end)
  end)
end) -- end describe

end -- end for

for _, strategy in helpers.each_strategy() do

describe("Admin API #" .. strategy, function()
  local client
  local bp, db, _
  setup(function()
    bp, db, _ = helpers.get_db_utils(strategy)

    assert(helpers.start_kong{
      database = strategy
    })

    client = assert(helpers.admin_client())
  end)
  teardown(function()
    helpers.stop_kong()
    if client then
      client:close()
    end
  end)

  describe("POST /routes", function()
    describe("Refresh the router", function()
      before_each(function()
        db:truncate("services")
        db:truncate("routes")
        db:truncate("workspaces")
        db:truncate("workspace_entities")
      end)

      it("doesn't create a route when it conflicts", function()
        -- create service and route in workspace default [[
        local demo_ip_service = bp.services:insert {
          name = "demo-ip",
          protocol = "http",
          host = "httpbin.org",
          path = "/ip",
        }

        bp.routes:insert({
          hosts = {"my.api.com" },
          paths = { "/my-uri" },
          methods = { "GET" },
          service = demo_ip_service,
        })
        -- ]]

        -- create a workspace and add a service in it [[
        local ws = bp.workspaces:insert {
          name = "w1"
        }

        bp.services:insert_ws ({
          name = "demo-anything",
          protocol = "http",
          host = "httpbin.org",
          path = "/anything",
        }, ws)
        -- ]]

        -- route collides with one in default workspace
        assert.res_status(409, client:post("/w1/services/demo-anything/routes", {
          body = {
            hosts = {"my.api.com" },
            paths = { "/my-uri" },
            methods = { "GET" },
          },
          headers = {["Content-Type"] = "application/json"},
        }))

        -- add different service to the default workspace
        bp.services:insert {
          name = "demo-default",
          protocol = "http",
          host = "httpbin.org",
          path = "/default",
        }

        -- allows adding service colliding with another in the same workspace
        assert.res_status(201, client:post("/default/services/demo-default/routes", {
          body = {
            methods = { "GET" },
            hosts = {"my.api.com"},
            paths = { "/my-uri" },
          },
          headers = {["Content-Type"] = "application/json"}
        }))
      end)

      it("doesn't allow creating routes that collide in path and have no host", function()
        local ws_name = utils.uuid()
        local ws = bp.workspaces:insert {
          name = ws_name
        }

        bp.services:insert {
          name = "demo-ip",
          protocol = "http",
          host = "httpbin.org",
          path = "/ip",
        }

        bp.services:insert_ws ({
          name = "demo-anything",
          protocol = "http",
          host = "httpbin.org",
          path = "/anything",
        }, ws)

        assert.res_status(201, client:post("/default/services/demo-ip/routes", {
          body = {
            paths = { "/my-uri" },
            methods = { "GET" },
          },
          headers = {["Content-Type"] = "application/json"},
        }))

        assert.res_status(409, client:post("/".. ws_name.."/services/demo-anything/routes", {
          body = {
            paths = { "/my-uri" },
            methods = { "GET" },
          },
          headers = {["Content-Type"] = "application/json"},
        }))
      end)

      it("route PATCH checks collision", function()
        local ws_name = utils.uuid()
        local ws = bp.workspaces:insert {
          name = ws_name
        }

        bp.services:insert {
          name = "demo-ip",
          protocol = "http",
          host = "httpbin.org",
          path = "/ip",
        }

        bp.services:insert_ws ({
          name = "demo-anything",
          protocol = "http",
          host = "httpbin.org",
          path = "/anything",
        }, ws)

        assert.res_status(201, client:post("/default/services/demo-ip/routes", {
          body = {
            hosts = {"my.api.com" },
            paths = { "/my-uri" },
            methods = { "GET" },
          },
          headers = { ["Content-Type"] = "application/json"},
        }))

        local res = client:post("/" .. ws_name .. "/services/demo-anything/routes", {
          body = {
            hosts = {"my.api.com2" },
            paths = { "/my-uri" },
            methods = { "GET" },
          },
          headers = {["Content-Type"] = "application/json"},
        })
        res = cjson.decode(assert.res_status(201, res))

        -- route collides in different WS
        assert.res_status(409, client:patch("/" .. ws_name .. "/routes/".. res.id, {
          body = {
            hosts = {"my.api.com" },
            paths = { "/my-uri" },
            methods = { "GET" },
          },
          headers = {["Content-Type"] = "application/json"},
        }))
      end)
    end)
  end)
end) -- end describe

end -- end for
