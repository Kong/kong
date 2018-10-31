local dao_helpers = require "spec.02-integration.03-dao.helpers"
local DAOFactory  = require "kong.dao.factory"
local helpers     = require "spec.helpers"
local cjson       = require "cjson"
local utils       = require "kong.tools.utils"
local workspaces  = require "kong.workspaces"
local singletons  = require "kong.singletons"
local init_files  = require "kong.portal.migrations.01_initial_files"


dao_helpers.for_each_dao(function(kong_config)

describe("(#" .. kong_config.database .. ") Admin API workspaces", function()
  local client, dao

  setup(function()
    dao = assert(DAOFactory.new(kong_config))
    singletons.dao = dao

    dao:truncate_tables()
    helpers.dao:run_migrations()
    assert(helpers.start_kong({
      database = kong_config.database
    }))
    ngx.ctx.workspaces = nil
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
            meta = {
              color = "#92b6d5"
            }
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

        -- no files created, portal is off
        local files_count = dao.files:count()
        assert.equals(0, files_count)
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

      it("handles invalid meta json", function()
        local res = assert(client:send {
          method = "POST",
          path   = "/workspaces",
          body   = {
            name = "foo",
            meta = "{ color: red }" -- invalid json
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)

        assert.equals("meta is not a table", json.meta)
      end)

      it("creates default files if portal is ON", function()
        local files = dao.files:find_all()
        assert.equals(0, #files)


        local res = assert(client:send {
          method = "POST",
          path   = "/workspaces",
          body   = {
            name = "ws-with-portal",
            config = {
              portal = true
            }
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.is_true(utils.is_valid_uuid(json.id))
        assert.equals("ws-with-portal", json.name)
        assert.is_nil(json.comment)

        local files_count = helpers.with_current_ws(
          {json},
          function()
            return dao.files:count()
          end
        )

        assert.equals(#init_files, files_count)
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

        assert.equals(4, json.total)
        assert.equals(4, #json.data)
      end)

      it("returns 404 if called from other than default workspace", function()
        local res = assert(client:send {
          method = "GET",
          path   = "/bar/workspaces",
        })
        assert.res_status(404, res)

        res = assert(client:send {
          method = "GET",
          path   = "/default/workspaces",
        })
        assert.res_status(200, res)
      end)
    end)
  end)

  describe("/workspaces/:workspace", function()
    describe("PATCH", function()
      it("refuses to update the workspace name", function()
        local res = assert(client:send {
          method = "PATCH",
          path = "/workspaces/foo",
          body = {
            name = "new_foo",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)

        assert.equals("Cannot rename a workspace", json.message)
      end)
      it("updates an existing entity", function()
        local res = assert(client:send {
          method = "PATCH",
          path   = "/workspaces/foo",
          body   = {
            comment = "foo comment",
            meta = {
              color = "red"
            }
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals("foo comment", json.comment)
        assert.equals("red", json.meta.color)
      end)

      it("creates default files if portal is turned on", function()
        local res = assert(client:send {
          method = "POST",
          path   = "/workspaces",
          body   = {
            name = "rad-portal-man",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        assert.res_status(201, res)
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        local files_count = helpers.with_current_ws(
          {json},
          function()
            return dao.files:count()
          end
        )

        assert.equals(0, files_count)

        local res = assert(client:send {
          method = "PATCH",
          path   = "/workspaces/rad-portal-man",
          body   = {
            config = {
              portal = true
            }
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        local files_count = helpers.with_current_ws(
          {json},
          function()
            return dao.files:count()
          end
        )

        assert.equals(#init_files, files_count)
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
        assert.equals("red", json.meta.color)
      end)

      it("sends the appropriate status on an invalid entity", function()
        local res = assert(client:send {
          method = "GET",
          path   = "/workspaces/baz",
        })

        assert.res_status(404, res)
      end)

      it("returns 404 if we call from another workspace", function()
        local res = assert(client:send {
          method = "GET",
          path   = "/foo/workspaces/default",
        })
        assert.res_status(404, res)

        res = assert(client:send {
          method = "GET",
          path   = "/workspaces/foo",
        })
        assert.res_status(200, res)

        res = assert(client:send {
          method = "GET",
          path   = "/default/workspaces/foo",
        })
        assert.res_status(200, res)

        res = assert(client:send {
          method = "GET",
          path   = "/foo/workspaces/foo",
        })
        assert.res_status(200, res)
      end)

    end)

    describe("DELETE", function()
      it("refuses to delete default workspace", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/workspaces/default",
        })

        assert.res_status(400, res)
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

      it("refuses to delete a non empty workspace", function()
        local name = "blah"

        local res = assert(client:send {
          method = "POST",
          path = "/workspaces",
          body = { name = name },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(201, res)

        res = assert(client:send {
          method = "POST",
          path   = "/" .. name .. "/apis",
          body = {
            name = "foo",
            hosts = {"api.com"},
            upstream_url = helpers.mock_upstream_url
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(201, res)

        res = assert(client:send {
          method = "DELETE",
          path   = "/workspaces/" .. name,
        })
        assert.res_status(400, res)
      end)

    end)
  end)

  describe("/workspaces/:workspace/entites", function()
    local uuid1, uuid2

    lazy_setup(function()
      -- yayyyyyyy determinism!
      uuid1, uuid2 = "182f2cc8-008e-11e8-ba89-0ed5f89f718b",
                     "182f2f2a-008e-11e8-ba89-0ed5f89f718b"

      ngx.ctx.workspaces = {}
      local w = dao.workspaces:find_all({
        name = "foo",
      })
      ngx.ctx.workspaces = dao.workspaces:find_all({name = "default"})

      w = w[1].id

      assert(dao.workspace_entities:insert({
        workspace_id = w,
        workspace_name = "foo",
        entity_id = uuid1,
        unique_field_name = "name",
        entity_type = "foo",
      }))
      assert(dao.workspace_entities:insert({
        workspace_id = w,
        workspace_name = "bar",
        entity_id = uuid2,
        unique_field_name = "name",
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
        -- default, foo, blah
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
        lazy_setup(function()
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

          -- XXX if instead of inserting at the dao level we insert via the API,
          -- one test case will fail - ('{"message":"No workspace by name or id bar"}');
          -- investigate the root cause
          assert(dao.workspaces:insert {
              name = "bar",
          })
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

            assert.equals(entity.id, json[1].id)
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

        -- XXX nested workspaces disabled
        pending("on circular reference", function()
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

    lazy_setup(function()
      w_id = dao.workspaces:find_all({ name = "foo" })[1].id
      e_id = utils.uuid()

      assert(dao.workspace_entities:insert({
        workspace_id = w_id,
        workspace_name = "foo",
        entity_id = e_id,
        unique_field_name = "name",
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

dao_helpers.for_each_dao(function(kong_config)
describe("Admin API #" .. kong_config.database, function()
  local client
  local dao
  setup(function()
    dao = assert(DAOFactory.new(kong_config))
    singletons.dao = dao

    dao:truncate_tables()
    dao:run_migrations()

    assert(helpers.start_kong{
      database = kong_config.database
    })
  end)
  teardown(function()
    helpers.stop_kong()
  end)

  describe("POST /apis", function()
    describe("Refresh the router", function()
      before_each(function()
        ngx.ctx.workspaces = nil
        dao:truncate_tables()
        client = assert(helpers.admin_client())
      end)
      after_each(function()
        if client then client:close() end
      end)
      it("doesn't create an API when it conflicts", function()
          local res = assert(client:send {
            method = "POST",
            path = "/apis",
            body = {
              uris = "/my-uri",
              name = "my-api",
              methods = "GET",
              hosts = "my.api.com",
              upstream_url = "http://api.com"
            },
            headers = {["Content-Type"] = "application/json"}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          res = assert(client:send {
                         method = "POST",
                         path = "/workspaces",
                         body = {
                           name = "foo",
                         },
                         headers = {["Content-Type"] = "application/json"}
          })

          assert.res_status(201, res)

          -- route collides in different WS
          res = assert(client:send {
                         method = "POST",
                         path = "/foo/apis",
                         body = {
                           uris = "/my-uri",
                           name = "my-api",
                           methods = "GET",
                           hosts = "my.api.com",
                           upstream_url = "http://api.com"
                         },
                         headers = {["Content-Type"] = "application/json"}
          })
          assert.res_status(409, res)

          -- colliding in same WS, no problemo
          res = assert(client:send {
                         method = "POST",
                         path = "/apis",
                         body = {
                           uris = "/my-uri",
                           name = "my-api2",
                           methods = "GET,POST",
                           hosts = "my.api.com",
                           upstream_url = "http://api.com"
                         },
                         headers = {["Content-Type"] = "application/json"}
          })
          res = cjson.decode(assert.res_status(201, res))

          -- Delete the existing ones
          res = assert(client:send {
                         method = "DELETE",
                         path = "/apis/" .. res.id,
                         headers = {["Content-Type"] = "application/json"}
          })
          assert.res_status(204, res)

          res = assert(client:send {
                         method = "DELETE",
                         path = "/apis/" .. json.id,
                         headers = {["Content-Type"] = "application/json"}
          })
          assert.res_status(204, res)

          -- Now we can create it
          res = assert(client:send {
                         method = "POST",
                         path = "/foo/apis",
                         body = {
                           uris = "/my-uri",
                           name = "my-api",
                           methods = "GET",
                           hosts = "my.api.com",
                           upstream_url = "http://api.com"
                         },
                         headers = {["Content-Type"] = "application/json"}
          })
          assert.res_status(201, res)
      end)
      it("modifies an api via PUT /apis", function()
          local res = assert(client:send {
            method = "POST",
            path = "/apis",
            body = {
              uris = "/my-uri",
              name = "my-api",
              methods = "GET",
              hosts = "my.api.com",
              upstream_url = "http://api.com"
            },
            headers = {["Content-Type"] = "application/json"}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          res = assert(client:send {
                         method = "POST",
                         path = "/workspaces",
                         body = {
                           name = "foo",
                         },
                         headers = {["Content-Type"] = "application/json"}
          })

          assert.res_status(201, res)

          -- modified ok
          res = assert(client:send {
            method = "PUT",
            path = "/apis",
            body = {
              id = json.id,
              uris = "/my-uri",
              name = "my-api",
              methods = "GET",
              hosts = "my.api.com",
              created_at = json.created_at,
              upstream_url = "http://api.com",
            },
            headers = {["Content-Type"] = "application/json"}
          })
          assert.res_status(200, res)

          --  create ok in different WS
          res = assert(client:send {
                         method = "POST",
                         path = "/foo/apis",
                         body = {
                           uris = "/my-uri",
                           name = "my-api",
                           methods = "GET",
                           hosts = "another",
                           upstream_url = "http://api.com"
                         },
                         headers = {["Content-Type"] = "application/json"}
          })
          body = assert.res_status(201, res)
          json = cjson.decode(body)

          --  can't modify it if it collides
          res = assert(client:send {
                         method = "PUT",
                         path = "/foo/apis",
                         body = {
                           id = json.id,
                           uris = "/my-uri",
                           name = "my-api",
                           methods = "GET",
                           hosts = "my.api.com",
                           upstream_url = "http://api.com"
                         },
                         headers = {["Content-Type"] = "application/json"}
          })
          assert.res_status(409, res)
        end)
      it("creates with PUT /apis without id", function()
        local res = assert(client:send {
                             method = "POST",
                             path = "/apis",
                             body = {
                               uris = "/my-uri",
                               name = "my-api",
                               methods = "GET",
                               hosts = "my.api.com",
                               upstream_url = "http://api.com"
                             },
                             headers = {["Content-Type"] = "application/json"}
        })
        assert.res_status(201, res)

        res = assert(client:send {
                       method = "POST",
                       path = "/workspaces",
                       body = {
                         name = "foo",
                       },
                       headers = {["Content-Type"] = "application/json"}
        })

        assert.res_status(201, res)

        -- creates in different ws an API that would swallow traffic
        res = assert(client:send {
                       method = "PUT",
                       path = "/foo/apis",
                       body = {
                         uris = "/my-uri",
                         name = "my-api",
                         methods = "GET",
                         hosts = "my.api.com",
                         upstream_url = "http://api.com"
                       },
                       headers = {["Content-Type"] = "application/json"}
        })
        assert.res_status(409, res)

      end)

      it("PATCH /apis/:name_or_id checks urls", function()

        local res = assert(client:send {
                             method = "POST",
                             path = "/apis",
                             body = {
                               uris = "/my-uri",
                               name = "my-api",
                               methods = "GET",
                               hosts = "my.api.com",
                               upstream_url = "http://api.com"
                             },
                             headers = {["Content-Type"] = "application/json"}
        })
        assert.res_status(201, res)

        res = assert(client:send {
                       method = "POST",
                       path = "/workspaces",
                       body = {
                         name = "foo",
                       },
                       headers = {["Content-Type"] = "application/json"}
        })

        assert.res_status(201, res)

        -- creates in different ws an API that would swallow traffic
        res = assert(client:send {
                       method = "POST",
                       path = "/foo/apis",
                       body = {
                         uris = "/my-uri",
                         name = "my-api",
                         methods = "GET",
                         hosts = "another",
                         upstream_url = "http://api.com"
                       },
                       headers = {["Content-Type"] = "application/json"}
        })
        local body = assert.res_status(201, res)

        res = assert(client:send {
                       method = "PATCH",
                       path = "/foo/apis/" .. cjson.decode(body).id,
                       body = {
                         uris = "/my-uri",
                         name = "my-api",
                         methods = "GET",
                         hosts = "my.api.com",
                         upstream_url = "http://api.com"
                       },
                       headers = {["Content-Type"] = "application/json"}
        })
        assert.res_status(409, res)
      end)
    end)
  end)
end)
end)

dao_helpers.for_each_dao(function(kong_config)
  describe("Admin API #" .. kong_config.database, function()
    local client

    local function any(t, p)
      return #(require("pl.tablex").filter(t, p)) > 0
    end

    local function post(path, body, headers, expected_status)
      headers = headers or {}
      if not headers["Content-Type"] then
        headers["Content-Type"] = "application/json"
      end

      if any(require("pl.tablex").keys(body), function(x) return x:match( "%[%]$") end) then
        headers["Content-Type"] = "application/x-www-form-urlencoded"
      end

      local res = assert(client:send{
        method = "POST",
        path = path,
        body = body or {},
        headers = headers
      })

      return cjson.decode(assert.res_status(expected_status or 201, res))
    end


    local function get(path, headers, expected_status)
      headers = headers or {}
      headers["Content-Type"] = "application/json"
      local res = assert(client:send{
        method = "GET",
        path = path,
        headers = headers
      })
      return cjson.decode(assert.res_status(expected_status or 200, res))
    end

    local function delete(path, body, headers, expected_status)
      headers = headers or {}
      headers["Content-Type"] = "application/json"
      local res = assert(client:send{
        method = "DELETE",
        path = path,
        headers = headers,
        body = body,
      })
      assert.res_status(expected_status or 204, res)
    end

    setup(function()
      helpers.get_db_utils(kong_config.database)

      assert(helpers.start_kong{
        database = kong_config.database
      })
      client = assert(helpers.admin_client())
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    it("increments counter on entity_type and workspace", function()
      local res

      -- 2 workspaces (default and ws1), each with 1 consumer
      post("/workspaces", {name = "ws1"})
      local c1 = post("/consumers", {username = "first"})
      post("/ws1/consumers", {username = "bob"})

      res = get("/workspaces/ws1/meta")
      assert.equal(1, res.counts.consumers)

      res = get("/workspaces/default/meta")
      assert.equal(1, res.counts.consumers)

      -- share c1 with ws1
      post("/workspaces/ws1/entities", {entities = c1.id})

      -- ws1 has 2 consumers now
      res = get("/workspaces/ws1/meta")
      assert.equal(2, res.counts.consumers)

      -- default still has 1
      res = get("/workspaces/default/meta")
      assert.equal(1, res.counts.consumers)

      -- delete the one only in ws1
      delete("/ws1/consumers/bob" )
      local res = get("/workspaces/ws1/meta")
      assert.equal(1, res.counts.consumers)

      -- delete the shared one (multiple ws are deleted ok)
      delete("/ws1/consumers/" .. c1.id)
      res = get("/workspaces/ws1/meta")
      assert.equal(0, res.counts.consumers)

      res = get("/workspaces/default/meta")
      assert.equal(0, res.counts.consumers)

      -- delete ws1
      delete("/workspaces/ws1")
      get("/workspaces/default/meta")

      -- ws1 doesn't exist anymore
      get("/workspaces/ws1/meta", nil, 404)
    end)

    it("unshare decrements counts", function()
      post("/workspaces", {name = "ws1"})
      local c1 = post("/consumers", {username = "first"})
      -- share c1 with ws1
      post("/workspaces/ws1/entities", {entities = c1.id})

      -- ws1 has 1 consumer now
      local res = get("/workspaces/ws1/meta")
      assert.equal(1, res.counts.consumers)

      -- unshare c1 with ws1
      delete("/workspaces/ws1/entities", {entities = c1.id})
      -- ws1 has 0 consumers now
      local res = get("/workspaces/ws1/meta")
      assert.equal(0, res.counts.consumers)

      delete("/workspaces/ws1") --cleanup
    end)

    it("increments counters from new dao entities", function()
      post("/workspaces", {name = "ws1"})
      post("/ws1/services", {name = "s1", host = "s1.com"})
      local res = get("/workspaces/ws1/meta")
      assert.equals(1, res.counts.services)

      delete("/ws1/services/s1")
      res = get("/workspaces/ws1/meta")
      assert.equals(0, res.counts.services)
      delete("/workspaces/ws1") --cleanup
    end)

    it("returns 404 if we call from another workspace", function()
      post("/workspaces", {name = "ws1"})

      local res = assert(client:send {
        method = "GET",
        path   = "/ws1/workspaces/default/meta",
      })
      assert.res_status(404, res)
    end)

  end)
end)
