local dao_helpers = require "spec.02-integration.03-dao.helpers"
local DAOFactory = require "kong.dao.factory"
local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"

local function run_with_ws(ws, cb)
  local old_ws = ngx.ctx.workspaces
  ngx.ctx.workspaces = ws
  cb()
  ngx.ctx.workspaces = old_ws
end

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

  -- theres a default limit of 100 requests that can be used per
  -- client keepalive connection. since this is a fairly large
  -- test suite and we have more than 100 client:send calls,
  -- we need to refresh the connection. doing some before every
  -- block isnt a major performance killer
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
        assert.equal(19, #json.resources)
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
        assert.is_table(json.resources)
        assert.is_table(json.actions)
        assert.equals(0, #json.resources)
        assert.equals(0, #json.actions)

        -- 'nil' is presented to the user; we are represented as 0 here
        run_with_ws(dao.workspaces:find_all(), function ()
          local row = dao.rbac_perms:find({ id = json.id })
          assert(0, row.resources)
          assert(0, row.actions)
        end)
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

        assert.not_number(json.resources)
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

      it("transforms actions and resources values (#regression)", function()
        -- ensure that resources and actions are disabled as human-readable
        -- structures (lists)
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/permissions/read-only",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.not_number(json.resources)
        assert.is_table(json.resources)
        assert.not_number(json.actions)
        assert.is_table(json.actions)

        -- test against an empty permission
        res = assert(client:send {
          method = "GET",
          path = "/rbac/permissions/foo",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.not_number(json.resources)
        assert.is_table(json.resources)
        assert.equals(0, #json.resources)
        assert.not_number(json.actions)
        assert.is_table(json.actions)
        assert.equals(0, #json.actions)
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
      local rows
      run_with_ws(dao.workspaces:find_all(), function ()
        rows = dao.rbac_roles:find_all()
      end)


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
      assert.equals(19, n)

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
      assert.equals(18, n)

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
      assert.equals(19, n)
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
      assert.equals(19, n)
    end)
  end)

  describe("/rbac/roles/:name_or_id/entities", function()
    describe("POST", function()
      local e_id, w_id

      setup(function()
        dao:truncate_tables()
        run_with_ws(dao.workspaces:find_all(), function ()
          assert(dao.rbac_roles:insert({
            name = "mock-role",
          }))

          -- workspace to test auto entity_type detection
          local w = assert(dao.workspaces:insert({
            name = "mock-workspace",
          }))
          w_id = w.id

          -- workspace to test auto entity_type detection
          local e = assert(dao.apis:insert({
            name = "mock-api",
            uris = "/",
            upstream_url = "http://httpbin.org"
          }))
          e_id = e.id
        end)
      end)

      it("associates an entity with a role", function()
        local res = assert(client:send {
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
        assert.equals("apis", json.entity_type)
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

  describe("/rbac/roles/:name_or_id/entities/:entity_id with ", function()
    local e_id

    setup(function()
      run_with_ws(dao.workspaces:find_all(), function ()
        e_id = assert(dao.apis:find_all({
          name = "mock-api",
        }))
      end)
    end)

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

  describe("/rbac/roles/:name_or_id/entities/permissions with" ..
    kong_config.database, function()
    local e_id

    setup(function()
      -- workspace to test auto entity_type detection
      run_with_ws(dao.workspaces:find_all(), function ()
        e_id = assert(dao.apis:find_all({
          name = "mock-api",
        }))[1].id
      end)

      local res = assert(client:send {
        method = "POST",
        path = "/rbac/roles/mock-role/entities",
        body = {
          entity_id = e_id,
          actions = "read,update",
        },
        headers = {
          ["Content-Type"] = "application/json"
        },
      })
      assert.res_status(201, res)
    end)

    describe("GET", function()
      it("displays the role-entities permissions map for the given role", function()
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/roles/mock-role/entities/permissions",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        table.sort(json[e_id])
        assert.same({ "read", "update" }, json[e_id])

        local n = 0
        for k in pairs(json) do
          n = n + 1
        end
        assert.same(1, n)
      end)
    end)
  end)

  describe("/rbac/roles/:name_or_id/endpoints with", function()
    setup(function()
      dao:truncate_tables()
      run_with_ws(dao.workspaces:find_all(), function ()
        assert(dao.rbac_roles:insert({
          name = "mock-role",
        }))

        assert(dao.workspaces:insert({
          name = "mock-workspace",
        }))
      end)
    end)

    describe("POST", function()
      it("creates a new role_endpoint", function()
        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/mock-role/endpoints",
          body = {
            workspace = "mock-workspace",
            endpoint = "foo",
            actions = "all",
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
        -- fuck you cassandra
        local test = kong_config.database == "cassandra" and pending or it

        test("on duplicate PK", function()
          local res = assert(client:send {
            method = "POST",
            path = "/rbac/roles/mock-role/endpoints",
            body = {
              workspace = "mock-workspace",
              endpoint = "foo",
              actions = "all",
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
              actions = "all",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })

          local body = assert.res_status(404, res)
          local json = cjson.decode(body)

          assert.matches("Workspace 'dne-workspace' does not exist",
                         json.message, nil, true)
        end)
        it("on invalid role", function()
          local res = assert(client:send {
            method = "POST",
            path = "/rbac/roles/dne-role/endpoints",
            body = {
              workspace = "mock-workspace",
              endpoint = "foo",
              actions = "all",
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

        assert.same(0, dao.rbac_role_entities:count())
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

        assert.same({ "read" }, json["mock-workspace"]["*"])
      end)
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
