local dao_helpers = require "spec.02-integration.03-dao.helpers"
local DAOFactory = require "kong.dao.factory"
local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"


dao_helpers.for_each_dao(function(kong_config)

describe("Admin API RBAC with " .. kong_config.database, function()
  local dao, client

  setup(function()
    dao = assert(DAOFactory.new(kong_config))
    dao:drop_schema()
    helpers.dao:run_migrations()

    assert(helpers.start_kong({
      database = kong_config.database
    }))
  end)

  before_each(function()
    if client then
      client:close()
    end

    client = assert(helpers.admin_client())
  end)

  teardown(function()
    if client then
      client:close()
    end

    dao:drop_schema()
    helpers.stop_kong()
  end)

  describe("/rbac/users", function()
    describe("POST", function()
      it("creates a new user", function()
        local res = assert(client:send {
          method = "POST",
          path = "/rbac/users",
          body = {
            name = "bob",
            user_token = "foo",
            comment = "bar",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.equal("bob", json.name)
        assert.equal("foo", json.user_token)
        assert.equal("bar", json.comment)
        assert.is_true(utils.is_valid_uuid(json.id))
        assert.is_true(json.enabled)
      end)

      it("creates a new user with non-default options", function()
        local res = assert(client:send {
          method = "POST",
          path = "/rbac/users",
          body = {
            name = "alice",
            user_token = "foor",
            enabled = false,
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.equal("alice", json.name)
        assert.equal("foor", json.user_token)
        assert.is_nil(json.comment)
        assert.is_true(utils.is_valid_uuid(json.id))
        assert.is_false(json.enabled)
      end)

      describe("errors", function()
        it("with duplicate tokens", function()
          local res = assert(client:send {
            method = "POST",
            path = "/rbac/users",
            body = {
              name = "bill",
              user_token = "aaa",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          assert.res_status(201, res)

          res = assert(client:send {
            method = "POST",
            path = "/rbac/users",
            body = {
              name = "jill",
              user_token = "aaa",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          assert.res_status(409, res)
        end)

        it("with duplicate names", function()
          local res = assert(client:send {
            method = "POST",
            path = "/rbac/users",
            body = {
              name = "jerry",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          assert.res_status(201, res)

          res = assert(client:send {
            method = "POST",
            path = "/rbac/users",
            body = {
              name = "jerry",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          assert.res_status(409, res)
        end)
      end)
    end)

    describe("GET", function()
      it("lists users", function()
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/users",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals(4, #json.data)
      end)

      -- TODO remove after master rebase - filter on cassandra
      -- is fixed in there
      local block = kong_config.database == "cassandra" and pending or it

      block("lists enabled users", function()
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/users",
          query = {
            enabled = true,
          },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals(3, #json.data)
      end)
    end)
  end)

  describe("/rbac/users/:name_or_id", function()
    local user1, user2

    describe("GET", function()
      it("retrieves a specific user by name", function()
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/users/bob",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        user1 = json
      end)

      it("retrieves a specific user by id", function()
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/users/" .. user1.id,
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        user2 = json

        assert.same(user1, user2)
      end)
    end)

    describe("PATCH", function()
      it("updates a specific user", function()
        local res = assert(client:send {
          method = "PATCH",
          path = "/rbac/users/bob",
          body = {
            comment = "new comment",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals("new comment", json.comment)
        assert.not_equals(json.comment, user1.comment)
      end)

      it("errors on nonexistent value", function()
        local res = assert(client:send {
          method = "PATCH",
          path = "/rbac/users/dne",
          body = {
            comment = "new comment",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        assert.res_status(404, res)
      end)
    end)

    describe("DELETE", function()
      it("deletes a given user", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/rbac/users/alice",
        })

        assert.res_status(204, res)

        res = assert(client:send {
          method = "GET",
          path = "/rbac/users",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals(3, #json.data)

        for i = 1, #json.data do
          assert.not_equals("alice", json.data[i].name)
        end
      end)
    end)
  end)

  describe("/rbac/roles", function()
    describe("POST", function()
      it("creates a new role", function()
        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles",
          body = {
            name = "new-role",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.equal("new-role", json.name)
        assert.is_true(utils.is_valid_uuid(json.id))
      end)

      it("creates a new role with an explicit uuid", function()
        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles",
          body = {
            id = utils.uuid(),
            name = "baz",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.equal("baz", json.name)
        assert.is_true(utils.is_valid_uuid(json.id))
      end)

      describe("errors", function()
        it("with duplicate names", function()
          local res = assert(client:send {
            method = "POST",
            path = "/rbac/roles",
            body = {
              name = "admin",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          assert.res_status(409, res)
        end)

        it("with no name", function()
          local res = assert(client:send {
            method = "POST",
            path = "/rbac/roles",
            body = {
              comment = "foo",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          assert.res_status(400, res)
        end)

        local id = utils.uuid()
        it("with duplicate ids", function()
          local res = assert(client:send {
            method = "POST",
            path = "/rbac/roles",
            body = {
              id = id,
              name = "duplicate-id",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          assert.res_status(201, res)

          res = assert(client:send {
            method = "POST",
            path = "/rbac/roles",
            body = {
              id = id,
              name = "duplicate-id",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          assert.res_status(409, res)
        end)
      end)
    end)

    describe("GET", function()
      it("lists roles", function()
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/roles",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals(6, #json.data)
      end)
    end)
  end)

  describe("/rbac/roles/:name_or_id", function()
    local role1, role2

    describe("GET", function()
      it("retrieves a specific role by name", function()
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/roles/read-only",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        role1 = json
      end)

      it("retrieves a specific role by id", function()
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/roles/" .. role1.id,
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        role2 = json

        assert.same(role1, role2)
      end)
    end)

    describe("PATCH", function()
      it("updates a specific role", function()
        local res = assert(client:send {
          method = "PATCH",
          path = "/rbac/roles/read-only",
          body = {
            comment = "new comment",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals("new comment", json.comment)
        assert.not_equals(json.comment, role1.comment)
      end)

      it("errors on nonexistent value", function()
        local res = assert(client:send {
          method = "PATCH",
          path = "/rbac/roles/dne",
          body = {
            comment = "new comment",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        assert.res_status(404, res)
      end)
    end)

    describe("DELETE", function()
      it("deletes a given role", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/rbac/roles/baz",
        })

        assert.res_status(204, res)

        res = assert(client:send {
          method = "GET",
          path = "/rbac/roles",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals(5, #json.data)

        for i = 1, #json.data do
          assert.not_equals("foo", json.data[i].name)
        end
      end)
    end)
  end)

  describe("/rbac/users/:name_or_id/roles", function()
    describe("POST", function()
      it("associates a role with a user", function()
        local res = assert(client:send {
          path = "/rbac/users/bob/roles",
          method = "POST",
          body = {
            roles = "read-only",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.same(1, #json.roles)
        assert.same("read-only", json.roles[1].name)
        assert.same("bob", json.user.name)
      end)

      it("associates multiple roles with a user", function()
        local res = assert(client:send {
          path = "/rbac/users/jerry/roles",
          method = "POST",
          body = {
            roles = "read-only,admin",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.same(2, #json.roles)
      end)

      describe("errors", function()
        it("when the user doesn't exist", function()
          local res = assert(client:send {
            path = "/rbac/users/dne/roles",
            method = "POST",
            body = {
              roles = "read-only",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          local body = assert.res_status(404, res)
          local json = cjson.decode(body)

          assert.same("No RBAC user by name or id dne", json.message)
        end)

        it("when the role doesn't exist", function()
          local res = assert(client:send {
            path = "/rbac/users/bob/roles",
            method = "POST",
            body = {
              roles = "dne",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.same("role not found with name 'dne'", json.message)
        end)

        do
          it("when duplicate relationships are attempted", function()
            local res = assert(client:send {
              path = "/rbac/users/bill/roles",
              method = "POST",
              body = {
                roles = "read-only",
              },
              headers = {
                ["Content-Type"] = "application/json",
              },
            })

            assert.res_status(201, res)

            res = assert(client:send {
              path = "/rbac/users/bill/roles",
              method = "POST",
              body = {
                roles = "read-only",
              },
              headers = {
                ["Content-Type"] = "application/json",
              },
            })

            -- TODO PK constraint not applied on cassandra
            if kong_config.database == "cassandra" then
              assert.res_status(201, res)
            else
              assert.res_status(409, res)
            end
          end)
        end
      end)
    end)

    describe("GET", function()
      it("displays the roles associated with the user", function()
        local res = assert(client:send {
          path = "/rbac/users/bob/roles",
          method = "GET",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same(1, #json.roles)
        assert.same("read-only", json.roles[1].name)
        assert.same("bob", json.user.name)

        res = assert(client:send {
          path = "/rbac/users/jerry/roles",
          method = "GET",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same(2, #json.roles)
        assert.same("jerry", json.user.name)
      end)
    end)

    describe("DELETE", function()
      it("removes a role associated with a user", function()
        local res = assert(client:send {
          path = "/rbac/users/bob/roles",
          method = "DELETE",
          body = {
            roles = "read-only",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        assert.res_status(204, res)

        res = assert(client:send {
          path = "/rbac/users/bob/roles",
          method = "GET",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same(0, #json.roles)
        assert.same("bob", json.user.name)
      end)

      it("removes only one role associated with a user", function()
        local res = assert(client:send {
          path = "/rbac/users/jerry/roles",
          method = "DELETE",
          body = {
            roles = "read-only",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        assert.res_status(204, res)

        res = assert(client:send {
          path = "/rbac/users/jerry/roles",
          method = "GET",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same(1, #json.roles)
        assert.same("admin", json.roles[1].name)
        assert.same("jerry", json.user.name)
      end)

      describe("errors", function()
        it("when the user doesn't exist", function()
          local res = assert(client:send {
            path = "/rbac/users/dne/roles",
            method = "DELETE",
            body = {
              roles = "read-only",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          local body = assert.res_status(404, res)
          local json = cjson.decode(body)

          assert.same("No RBAC user by name or id dne", json.message)
        end)

        it("when no roles are defined", function()
          local res = assert(client:send {
            path = "/rbac/users/bob/roles",
            method = "DELETE",
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.same("must provide >= 1 role", json.message)
        end)
      end)
    end)
  end)

  describe("/rbac/roles/:name_or_id/permissions", function()
    describe("GET", function()
      it("displays the permissions associated with the role", function()
        local res = assert(client:send {
          path = "/rbac/roles/read-only/permissions",
          method = "GET",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.not_nil(#json.endpoints)
        assert.not_nil(json.entities)
      end)
    end)
  end)

  describe("rbac defaults", function()
    setup(function()
      dao:drop_schema()
      helpers.dao:run_migrations()
    end)

    it("defines the default roles", function()
      local res = assert(client:send {
        path = "/rbac/roles/",
        method = "GET",
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      -- only three default roles
      assert.equal(3, #json.data)

      -- body contains those default roles names
      assert.matches("read-only", body, nil, true)
      assert.matches("admin", body, nil, true)
      assert.matches("super-admin", body, nil, true)
    end)

    it("defines the default endpoint permissions", function()
      local res, body

      -- check read-only role permissions
      res = assert(client:send {
        path = "/rbac/roles/read-only/endpoints/permissions",
        method = "GET",
      })

      body = assert.res_status(200, res)
      assert.matches("*", body, nil, true)
      assert.matches("read", body, nil, true)

      -- check read-only role permissions
      res = assert(client:send {
        path = "/rbac/roles/admin/endpoints/permissions",
        method = "GET",
      })

      body = assert.res_status(200, res)
      -- check existence of permissions for every endpoint, every action
      assert.matches("*", body, nil, true)
      assert.matches("delete", body, nil, true)
      assert.matches("create", body, nil, true)
      assert.matches("update", body, nil, true)
      assert.matches("read", body, nil, true)

      -- check existence of negative permissions for rbac
      -- TODO add check to make sure it's a negative permission - to be
      -- done after that endpoint returns said info
      assert.matches("rbac", body, nil, true)

      -- check read-only role permissions
      res = assert(client:send {
        path = "/rbac/roles/super-admin/endpoints/permissions",
        method = "GET",
      })

      body = assert.res_status(200, res)
      -- check existence of permissions for every endpoint, every action
      assert.matches("*", body, nil, true)
      assert.matches("delete", body, nil, true)
      assert.matches("create", body, nil, true)
      assert.matches("update", body, nil, true)
      assert.matches("read", body, nil, true)
      assert.not_matches("rbac", body, nil, true)
    end)

    it("defines no default entity permissions", function()
      local res = assert(client:send {
        path = "/rbac/roles/read-only/entities/permissions",
        method = "GET",
      })

      local body = assert.res_status(200, res)
      -- TODO needs improvement, when the corresponding endpoint gets
      -- to its final shape
      assert.same("{}", body, nil, true)
    end)

    it("will give user permissions when assigned to a role", function()
      -- this is bob
      -- bob has read-only access to all rbac resources
      local res = assert(client:send {
        method = "POST",
        path = "/rbac/users",
        body = {
          name = "bob",
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })
      assert.res_status(201, res)

      res = assert(client:send {
        method = "POST",
        path = "/rbac/users/bob/roles",
        body = {
          roles = "read-only",
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })

      local body = assert.res_status(201, res)
      local json = cjson.decode(body)

      assert.equals(1, #json.roles)
      assert.equals("bob", json.user.name)

      res = assert(client:send {
        method = "GET",
        path = "/rbac/users/bob/permissions",
      })

      body = assert.res_status(200, res)
      json = cjson.decode(body)

      -- TODO test permissions

      -- this is jerry
      -- jerry can view, create, update, and delete most resources
      local res = assert(client:send {
        method = "POST",
        path = "/rbac/users",
        body = {
          name = "jerry",
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })
      assert.res_status(201, res)

      res = assert(client:send {
        method = "POST",
        path = "/rbac/users/jerry/roles",
        body = {
          roles = "admin",
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })

      local body = assert.res_status(201, res)
      local json = cjson.decode(body)

      assert.equals(1, #json.roles)
      assert.equals("jerry", json.user.name)

      res = assert(client:send {
        method = "GET",
        path = "/rbac/users/jerry/permissions",
      })

      body = assert.res_status(200, res)
      json = cjson.decode(body)

      -- TODO test decoded permissions

      -- this is alice
      -- alice can do whatever the hell she wants
      local res = assert(client:send {
        method = "POST",
        path = "/rbac/users",
        body = {
          name = "alice",
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })
      assert.res_status(201, res)

      res = assert(client:send {
        method = "POST",
        path = "/rbac/users/alice/roles",
        body = {
          roles = "super-admin",
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })

      local body = assert.res_status(201, res)
      local json = cjson.decode(body)

      assert.equals(1, #json.roles)
      assert.equals("alice", json.user.name)

      res = assert(client:send {
        method = "GET",
        path = "/rbac/users/alice/permissions",
      })

      body = assert.res_status(200, res)
      json = cjson.decode(body)

      -- TODO test decoded permissions
    end)

    it("will give user permission regardless of their enabled status", function()
      -- this is herb
      -- herb has read-only access to all rbac resources
      -- but he is not enabled, so it doesn't matter!
      local res = assert(client:send {
        method = "POST",
        path = "/rbac/users",
        body = {
          name = "herb",
          enabled = false,
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })
      assert.res_status(201, res)

      res = assert(client:send {
        method = "POST",
        path = "/rbac/users/herb/roles",
        body = {
          roles = "read-only",
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })

      local body = assert.res_status(201, res)
      local json = cjson.decode(body)

      assert.equals(1, #json.roles)
      assert.equals("herb", json.user.name)

      res = assert(client:send {
        method = "GET",
        path = "/rbac/users/herb/permissions",
      })

      body = assert.res_status(200, res)
      json = cjson.decode(body)

      -- TODO test decoded permissions
    end)
  end)

  -- TODO stateful tests: so ugly
  local e_id, w_id

  describe("/rbac/roles/:name_or_id/entities", function()
    describe("POST", function()
      it("associates an entity with a role", function()
        local res, body, json

        -- create some entity
        res = assert(client:send {
          method = "POST",
          path = "/plugins",
          body = {
            name = "key-auth",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        body = assert.res_status(201, res)
        json = cjson.decode(body)

        -- save the entity's id
        e_id = json.id

        -- create a workspace
        res = assert(client:send {
          method = "POST",
          path = "/workspaces",
          body = {
            name = "ws1",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        body = assert.res_status(201, res)
        json = cjson.decode(body)

        w_id = json.id

        res = assert(client:send {
          method = "POST",
          path = "/rbac/roles",
          body = {
            name = "mock-role",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        assert.res_status(201, res)

        res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/mock-role/entities",
          body = {
            entity_id = e_id,
            actions = "read",
          },
          headers = {
            ["Content-Type"] = "application/json"
          },
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.equals(json.entity_id, e_id)
        assert.is_false(json.negative)
        assert.equals("plugins", json.entity_type)
      end)

      it("detects an entity as a workspace", function()
        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/mock-role/entities",
          body = {
            entity_id = w_id,
            actions = "read",
          },
          headers = {
            ["Content-Type"] = "application/json"
          },
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.equals("workspaces", json.entity_type)
      end)

      describe("errors", function()
        it("when the given role does not exist", function()
        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/dne-role/entities",
          body = {
            entity_id = w_id,
            actions = "read",
          },
          headers = {
            ["Content-Type"] = "application/json"
          },
        })

        assert.res_status(404, res)
        end)
      end)
    end)

    describe("GET", function()
      it("retrieves a list of entities associated with the role", function()
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/roles/mock-role/entities",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same(2, json.total)
        assert.same(2, #json.data)
        assert.same({ "read" }, json.data[1].actions)
      end)

      it("limits the size of returned entities", function()
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/roles/mock-role/entities?size=1",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same(2, json.total)
        assert.same(1, #json.data)
        assert.not_nil(json.next)
        assert.not_nil(json.offset)
      end)

      describe("errors", function()
        it("when the given role does not exist", function()
          local res = assert(client:send {
            method = "GET",
            path = "/rbac/roles/dne-role/entities",
          })

          assert.res_status(404, res)
        end)
      end)
    end)
  end)

  describe("/rbac/roles/:name_or_id/entities/:entity_id", function()
    describe("GET", function()
      it("fetches a single relation definition", function()
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/roles/mock-role/entities/" .. e_id,
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same(e_id, json.entity_id)
        assert.same({ "read" }, json.actions)
      end)

      describe("errors", function()
        it("when the given role does not exist", function()
          local res = assert(client:send {
            method = "GET",
            path = "/rbac/roles/dne-role/entities",
          })

          assert.res_status(404, res)
        end)
        it("when the given entity does not exist", function()
          local res = assert(client:send {
            method = "GET",
            path = "/rbac/roles/mock-role/entities/" .. utils.uuid(),
          })

          assert.res_status(404, res)
        end)
        it("when the given entity is not a valid UUID", function()
          local res = assert(client:send {
            method = "GET",
            path = "/rbac/roles/mock-role/entities/foo",
          })

          assert.res_status(400, res)
        end)
      end)
    end)

    describe("PATCH", function()
      it("updates a given entity", function()
        local res = assert(client:send {
          method = "PATCH",
          path = "/rbac/roles/mock-role/entities/" .. e_id,
          body = {
            comment = "foo",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.is_true(utils.is_valid_uuid(json.role_id))
        assert.is_true(utils.is_valid_uuid(json.entity_id))
        assert.same("foo", json.comment)
        assert.same({ "read" }, json.actions)
      end)

      it("update the relationship actions and displays them properly", function()
        local res = assert(client:send {
          method = "PATCH",
          path = "/rbac/roles/mock-role/entities/" .. e_id,
          body = {
            actions = "read,update,delete",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same("foo", json.comment)

        table.sort(json.actions)
        assert.same({ "delete", "read", "update" }, json.actions)
      end)

      describe("errors", function()
        it("when the given role does not exist", function()
          local res = assert(client:send {
            method = "PATCH",
            path = "/rbac/roles/dne-role/entities/" .. e_id,
            body = {
              comment = "foo",
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          assert.res_status(404, res)
        end)
        it("when the given entity does not exist", function()
          local res = assert(client:send {
            method = "PATCH",
            path = "/rbac/roles/mock-role/entities/" .. utils.uuid(),
            body = {
              comment = "foo",
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          assert.res_status(404, res)
        end)
        it("when the given entity is not a valid UUID", function()
          local res = assert(client:send {
            method = "DELETE",
            path = "/rbac/roles/mock-role/entities/foo",
            body = {
              comment = "foo",
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          assert.res_status(400, res)
        end)
        it("when the body is empty", function()
          local res = assert(client:send {
            method = "PATCH",
            path = "/rbac/roles/mock-role/entities/" .. e_id,
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          assert.res_status(400, res)
        end)
      end)
    end)

    describe("DELETE", function()
      it("removes an entity", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/rbac/roles/mock-role/entities/" .. e_id,
        })

        assert.res_status(204, res)

        assert.same(1, dao.rbac_role_entities:count())
      end)

      describe("errors", function()
        it("when the given role does not exist", function()
          local res = assert(client:send {
            method = "DELETE",
            path = "/rbac/roles/dne-role/entities/" .. e_id,
          })

          assert.res_status(404, res)
        end)
        it("when the given entity does not exist", function()
          local res = assert(client:send {
            method = "DELETE",
            path = "/rbac/roles/mock-role/entities/" .. utils.uuid(),
          })

          assert.res_status(404, res)
        end)
        it("when the given entity is not a valid UUID", function()
          local res = assert(client:send {
            method = "DELETE",
            path = "/rbac/roles/mock-role/entities/foo",
          })

          assert.res_status(400, res)
        end)
      end)
    end)
  end)

  describe("/rbac/roles/:name_or_id/entities/permissions", function()
    describe("GET", function()
      it("displays the role-entities permissions map for the given role", function()
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/roles/mock-role/entities/permissions",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        -- TODO permissions tests
      end)
    end)
  end)

  describe("/rbac/roles/:name_or_id/endpoints with", function()
    describe("POST", function()
      it("creates a new role_endpoint", function()
        local res

        res = assert(client:send {
          method = "POST",
          path = "/workspaces",
          body = {
            name = "mock-workspace",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(201, res)

        res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/mock-role/endpoints",
          body = {
            workspace = "mock-workspace",
            endpoint = "foo",
            actions = "*",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.same("mock-workspace", json.workspace)
        assert.same("foo", json.endpoint)

        table.sort(json.actions)
        assert.same({ "create", "delete", "read", "update" }, json.actions)
        assert.is_false(json.negative)
        assert.is_nil(json.comment)
      end)

      it("creates a new endpoint with similar PK elements", function()
        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/mock-role/endpoints",
          body = {
            workspace = "mock-workspace",
            endpoint = "*",
            actions = "read",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.same("mock-workspace", json.workspace)
        assert.same("*", json.endpoint)

        assert.same({ "read" }, json.actions)
        assert.is_false(json.negative)
        assert.is_nil(json.comment)
      end)

      describe("errors", function()
        -- cassandra cannot apply the PK constraint here
        -- FIXME on cassandra
        local block = kong_config.database == "cassandra" and pending or it
        block("on duplicate PK", function()
          local res = assert(client:send {
            method = "POST",
            path = "/rbac/roles/mock-role/endpoints",
            body = {
              workspace = "mock-workspace",
              endpoint = "foo",
              actions = "*",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          assert.res_status(409, res)
        end)

        it("on invalid workspace", function()
          local res = assert(client:send {
            method = "POST",
            path = "/rbac/roles/mock-role/endpoints",
            body = {
              workspace = "dne-workspace",
              endpoint = "foo",
              actions = "*",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          local body = assert.res_status(404, res)
          local json = cjson.decode(body)

          assert.matches("Workspace dne-workspace does not exist",
                         json.message, nil, true)
        end)
        it("on invalid role", function()
          local res = assert(client:send {
            method = "POST",
            path = "/rbac/roles/dne-role/endpoints",
            body = {
              workspace = "mock-workspace",
              endpoint = "foo",
              actions = "*",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          assert.res_status(404, res)
        end)
      end)
    end)

    describe("GET", function()
      it("retrieves a list of entities associated with the role", function()
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/roles/mock-role/endpoints",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same(2, json.total)
        assert.same(2, #json.data)
      end)

      it("limits the size of returned entities", function()
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/roles/mock-role/endpoints?size=1",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same(2, json.total)
        assert.same(1, #json.data)
        assert.not_nil(json.next)
        assert.not_nil(json.offset)
      end)

      describe("errors", function()
        it("when the given role does not exist", function()
          local res = assert(client:send {
            method = "GET",
            path = "/rbac/roles/dne-role/endpoints",
          })

          assert.res_status(404, res)
        end)
      end)
    end)
  end)

  describe("/rbac/roles/:name_or_id/endpoints/:workspace/:endpoint",
    function()
    describe("GET", function()
      it("retrieves a single entity", function()
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/roles/mock-role/endpoints/mock-workspace/foo",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals("mock-workspace", json.workspace)
        assert.equals("foo", json.endpoint)

        table.sort(json.actions)
        assert.same({ "create", "delete", "read", "update" }, json.actions)
      end)

      describe("errors", function()
        it("when the given role does not exist", function()
          local res = assert(client:send {
            method = "GET",
            path = "/rbac/roles/dne-role/endpoints/mock-workspace/foo",
          })

          assert.res_status(404, res)
        end)
        it("when the given workspace does not exist", function()
          local res = assert(client:send {
            method = "GET",
            path = "/rbac/roles/mock-role/endpoints/dne-workspace/foo",
          })

          assert.res_status(404, res)
        end)
        it("when the given endpoint does not exist", function()
          local res = assert(client:send {
            method = "GET",
            path = "/rbac/roles/mock-role/endpoints/mock-workspace/bar",
          })

          assert.res_status(404, res)
        end)
      end)
    end)

    describe("PATCH", function()
      it("updates a given endpoint", function()
        local res = assert(client:send {
          method = "PATCH",
          path = "/rbac/roles/mock-role/endpoints/mock-workspace/foo",
          body = {
            comment = "foo",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.is_true(utils.is_valid_uuid(json.role_id))
        assert.same("foo", json.comment)
        table.sort(json.actions)
        assert.same({ "create", "delete", "read", "update" }, json.actions)
      end)

      it("update the relationship actions and displays them properly", function()
        local res = assert(client:send {
          method = "PATCH",
          path = "/rbac/roles/mock-role/endpoints/mock-workspace/foo",
          body = {
            actions = "read,update,delete",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same("foo", json.comment)

        table.sort(json.actions)
        assert.same({ "delete", "read", "update" }, json.actions)
      end)

      describe("errors", function()
        it("when the given role does not exist", function()
          local res = assert(client:send {
            method = "PATCH",
            path = "/rbac/roles/dne-role/endpoints/mock-workspace/foo",
            body = {
              comment = "foo",
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          assert.res_status(404, res)
        end)
        it("when the given workspace does not exist", function()
          local res = assert(client:send {
            method = "PATCH",
            path = "/rbac/roles/mock-role/endpoints/dne-workspace/foo",
            body = {
              comment = "foo",
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          assert.res_status(404, res)
        end)
        it("when the given endpoint does not exist", function()
          local res = assert(client:send {
            method = "PATCH",
            path = "/rbac/roles/mock-role/endpoints/mock-workspace/bar",
            body = {
              comment = "foo",
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          assert.res_status(404, res)
        end)
        it("when the body is empty", function()
          local res = assert(client:send {
            method = "PATCH",
            path = "/rbac/roles/mock-role/endpoints/mock-workspace/foo",
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          assert.res_status(400, res)
        end)
      end)
    end)

    describe("DELETE", function()
      it("removes an endpoint association", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/rbac/roles/mock-role/endpoints/mock-workspace/foo",
        })

        assert.res_status(204, res)
        -- TODO review dao calls in this file - workspaces/rbac
        -- dao integration has rough edges
        assert.same(1, dao.rbac_role_entities:count())
      end)

      describe("errors", function()
        it("when the given role does not exist", function()
          local res = assert(client:send {
            method = "DELETE",
            path = "/rbac/roles/dne-role/endpoints/mock-workspace/foo"
          })

          assert.res_status(404, res)
        end)
        it("when the given workspace does not exist", function()
          local res = assert(client:send {
            method = "DELETE",
            path = "/rbac/roles/mock-role/endpoints/dne-workspace/foo"
          })

          assert.res_status(404, res)
        end)
        it("when the given endpoint does not exist", function()
          local res = assert(client:send {
            method = "DELETE",
            path = "/rbac/roles/mock-role/endpoints/mock-workspace/bar"
          })

          assert.res_status(404, res)
        end)
      end)
    end)
  end)

  describe("/rbac/roles/:name_or_id/endpoints/permissions", function()
    describe("GET", function()
      it("displays the role-endpoints permissions map for the given role", function()
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/roles/mock-role/endpoints/permissions",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        -- TODO improve this - test for the actual perms map
        assert(json)
      end)
    end)
  end)
end)

end)

for _, h in ipairs({ "", "Custom-Auth-Token" }) do
  describe("Admin API", function()
    local client
    local expected = h == "" and "Kong-RBAC-Token" or h

    setup(function()
      helpers.dao:run_migrations()
      assert(helpers.start_kong({
        rbac_auth_header = h ~= "" and h or nil,
      }))

      client = assert(helpers.admin_client())
    end)

    teardown(function()
      if client then
        client:close()
      end

      helpers.stop_kong()
    end)

    it("sends the rbac_auth_header value in ACAH preflight response", function()
      local res = assert(client:send {
        method = "OPTIONS",
        path   = "/",
      })

      assert.res_status(204, res)
      assert.matches("Content-Type, " .. expected,
                     res.headers["Access-Control-Allow-Headers"], nil, true)
    end)
  end)
end
