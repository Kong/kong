local dao_helpers = require "spec.02-integration.03-dao.helpers"
local DAOFactory = require "kong.dao.factory"
local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"


dao_helpers.for_each_dao(function(kong_config)

describe("Admin API RBAC with " .. kong_config.database, function()
  local client
  local dao

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

    -- explicitly clear tables here, as we work on both psql and c*
    dao:truncate_tables()

    helpers.stop_kong()
  end)

  describe("/rbac/users with " .. kong_config.database, function()
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

      it("lists enabled users", function()
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

  describe("/rbac/users/:name_or_id with " .. kong_config.database, function()
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

  describe("/rbac/roles with " .. kong_config.database, function()
    describe("POST", function()
      it("creates a new role", function()
        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles",
          body = {
            name = "read-only",
            comment = "bar",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.equal("read-only", json.name)
        assert.equal("bar", json.comment)
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

          assert.res_status(201, res)

          res = assert(client:send {
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
              name = "super-admin",
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
              name = "super-admin",
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

        assert.equals(4, #json.data)
      end)
    end)
  end)

  describe("/rbac/roles/:name_or_id with " .. kong_config.database, function()
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

        assert.equals(3, #json.data)

        for i = 1, #json.data do
          assert.not_equals("foo", json.data[i].name)
        end
      end)
    end)
  end)

  describe("/rbac/permissions with " .. kong_config.database, function()
    describe("POST", function()
      it("creates a new permission", function()
        local res = assert(client:send {
          method = "POST",
          path = "/rbac/permissions",
          body = {
            name = "read-only",
            resources = "all",
            actions = "read",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.equal("read-only", json.name)
        assert.same({ "read" }, json.actions)
        assert.equal(18, #json.resources)
        assert.is_true(utils.is_valid_uuid(json.id))
      end)

      it("creates a new permission with empty (default) bitfields", function()
        local res = assert(client:send {
          method = "POST",
          path = "/rbac/permissions",
          body = {
            name = "foo",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.equal("foo", json.name)
        assert.is_true(utils.is_valid_uuid(json.id))
        assert.is_nil(json.resources)
        assert.is_nil(json.actions)

        -- 'nil' is presented to the user; we are represented as 0 here
        local row = dao.rbac_perms:find({ id = json.id })
        assert(0, row.resources)
        assert(0, row.actions)
      end)

      describe("errors", function()
        it("with duplicate names", function()
          local res = assert(client:send {
            method = "POST",
            path = "/rbac/permissions",
            body = {
              name = "full",
              resources = "all",
              actions = "all",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          assert.res_status(201, res)

          res = assert(client:send {
            method = "POST",
            path = "/rbac/permissions",
            body = {
              name = "full",
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
            path = "/rbac/permissions",
            body = {
              resources = "all",
              actions = "all",
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
            path = "/rbac/permissions",
            body = {
              id = id,
              name = "no-rbac",
              actions = "all",
              resources = "rbac",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          assert.res_status(201, res)

          res = assert(client:send {
            method = "POST",
            path = "/rbac/permissions",
            body = {
              id = id,
              name = "no-rbac",
              actions = "all",
              resources = "rbac",
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
      it("lists permissions", function()
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/permissions",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals(4, #json.data)
      end)
    end)
  end)

  describe("/rbac/permissions/:name_or_id with " .. kong_config.database, function()
    local permission1, permission2

    describe("GET", function()
      it("retrieves a specific permission by name", function()
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/permissions/read-only",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        permission1 = json
      end)

      it("retrieves a specific permission by id", function()
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/permissions/" .. permission1.id,
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        permission2 = json

        assert.same(permission1, permission2)
      end)
    end)

    describe("PATCH", function()
      it("updates a specific permission", function()
        local res = assert(client:send {
          method = "PATCH",
          path = "/rbac/permissions/read-only",
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
        assert.not_equals(json.comment, permission1.comment)
      end)

      it("errors on nonexistent value", function()
        local res = assert(client:send {
          method = "PATCH",
          path = "/rbac/permissions/dne",
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
      it("deletes a given permission", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/rbac/permissions/foo",
        })

        assert.res_status(204, res)

        res = assert(client:send {
          method = "GET",
          path = "/rbac/permissions",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals(3, #json.data)

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
          -- cassandra cannot apply the PK constraint here
          local test = kong_config.database == "cassandra" and pending or it
          test("when duplicate relationships are attempted", function()
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

            assert.res_status(409, res)
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
    describe("POST", function()
      it("associates a permissions object with a role", function()
        local res = assert(client:send {
          path = "/rbac/roles/read-only/permissions",
          method = "POST",
          body = {
            permissions = "read-only",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.same("read-only", json.role.name)
        assert.same(1, #json.permissions)
      end)

      it("associates multiple permissions with a role", function()
        local res = assert(client:send {
          path = "/rbac/roles/admin/permissions",
          method = "POST",
          body = {
            permissions = "full,no-rbac",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.same(2, #json.permissions)
        assert.same("admin", json.role.name)
      end)

      describe("errors", function()
        it("when the role doesn't exist", function()
          local res = assert(client:send {
            path = "/rbac/roles/dne/permissions",
            method = "POST",
            body = {
              permissions = "read-only",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          local body = assert.res_status(404, res)
          local json = cjson.decode(body)

          assert.same("No RBAC role by name or id dne", json.message)
        end)

        it("when the role doesn't exist", function()
          local res = assert(client:send {
            path = "/rbac/roles/read-only/permissions",
            method = "POST",
            body = {
              permissions = "dne",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.same("perm not found with name 'dne'", json.message)
        end)

        do
          -- cassandra cannot apply the PK constraint here
          local test = kong_config.database == "cassandra" and pending or it
          test("when duplicate relationships are attempted", function()
            local res = assert(client:send {
              path = "/rbac/roles/super-admin/permissions",
              method = "POST",
              body = {
                permissions = "full",
              },
              headers = {
                ["Content-Type"] = "application/json",
              },
            })

            assert.res_status(201, res)

            res = assert(client:send {
              path = "/rbac/roles/super-admin/permissions",
              method = "POST",
              body = {
                permissions = "full",
              },
              headers = {
                ["Content-Type"] = "application/json",
              },
            })

            assert.res_status(409, res)
          end)
        end
      end)
    end)

    describe("GET", function()
      it("displays the permissions associated with the role", function()
        local res = assert(client:send {
          path = "/rbac/roles/read-only/permissions",
          method = "GET",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same(1, #json.permissions)

        res = assert(client:send {
          path = "/rbac/roles/admin/permissions",
          method = "GET",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same(2, #json.permissions)
        assert.same("admin", json.role.name)
      end)
    end)

    describe("DELETE", function()
      it("removes a permission associated with a role", function()
        local res = assert(client:send {
          path = "/rbac/roles/read-only/permissions",
          method = "DELETE",
          body = {
            permissions = "read-only",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        assert.res_status(204, res)

        res = assert(client:send {
          path = "/rbac/roles/read-only/permissions",
          method = "GET",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same(0, #json.permissions)
        assert.same("read-only", json.role.name)
      end)

      it("removes only one permission associated with a role", function()
        local res = assert(client:send {
          path = "/rbac/roles/admin/permissions",
          method = "DELETE",
          body = {
            permissions = "no-rbac",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        assert.res_status(204, res)

        res = assert(client:send {
          path = "/rbac/roles/admin/permissions",
          method = "GET",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same(1, #json.permissions)
        assert.same("full", json.permissions[1].name)
        assert.same("admin", json.role.name)
      end)

      describe("errors", function()
        it("when the role doesn't exist", function()
          local res = assert(client:send {
            path = "/rbac/roles/dne/permissions",
            method = "DELETE",
            body = {
              permissions = "read-only",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          local body = assert.res_status(404, res)
          local json = cjson.decode(body)

          assert.same("No RBAC role by name or id dne", json.message)
        end)

        it("when no permissions are defined", function()
          local res = assert(client:send {
            path = "/rbac/roles/read-only/permissions",
            method = "DELETE",
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)

          assert.same("must provide >= 1 permission", json.message)
        end)
      end)
    end)
  end)

  describe("rbac defaults", function()
    setup(function()
      -- hard drop of -everything-
      -- including the migrations tracker. the next time we call run_migrations()
      -- we will get a brand new environment as we would expect to see on a
      -- fresh kong install
      -- n.b. this is _very_ expensive, particularly with c*, so we avoid it
      -- until now, as here we care about testing defaults and migration results
      dao:drop_schema()
      helpers.run_migrations(dao)
    end)

    it("defines the default roles", function()
      local rows = dao.rbac_roles:find_all()

      assert.equals(3, #rows)

      -- yes, this is O(terrible)
      local default_names = {}
      for i = 1, #rows do
        default_names[#default_names + 1] = rows[i].name
      end
      for _, elt in ipairs({ "read-only", "admin", "super-admin" }) do
        assert.is_true(utils.table_contains(default_names, elt))
      end
    end)

    it("defines the default permissions", function()
      local rows = dao.rbac_perms:find_all()

      assert.equals(3, #rows)

      -- yes, this is O(terrible)
      local default_names = {}
      for i = 1, #rows do
        default_names[#default_names + 1] = rows[i].name
      end
      for _, elt in ipairs({ "read-only", "full-access", "no-rbac" }) do
        assert.is_true(utils.table_contains(default_names, elt))
      end
    end)

    it("will give user permissions when assigned the appropriate role", function()
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

      local n = 0
      for k, v in pairs(json) do
        n = n + 1
        assert.is_false(utils.table_contains(json[k], "create"))
        assert.is_false(utils.table_contains(json[k], "update"))
        assert.is_false(utils.table_contains(json[k], "delete"))
      end
      assert.equals(18, n)

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

      local n = 0
      for k, v in pairs(json) do
        n = n + 1
        assert.not_equals("rbac", k)
      end
      assert.equals(17, n)

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

      local n = 0
      for k, v in pairs(json) do
        n = n + 1
        assert.equals(4, #json[k])
      end
      assert.equals(18, n)
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

      local n = 0
      for k, v in pairs(json) do
        n = n + 1
        assert.is_false(utils.table_contains(json[k], "create"))
        assert.is_false(utils.table_contains(json[k], "update"))
        assert.is_false(utils.table_contains(json[k], "delete"))
      end
      assert.equals(18, n)
    end)
  end)
end)

end)

for _, h in ipairs({ "", "Custom-Auth-Token" }) do
  describe("Admin API", function()
    local client

    local expected = h == "" and "Kong-Admin-Token" or h

    setup(function()
      helpers.run_migrations()
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
