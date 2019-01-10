local dao_helpers = require "spec.02-integration.03-dao.helpers"
local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"
local ee_helpers = require "spec-ee.helpers"

local client

local function post(path, body, headers, expected_status)
  headers = headers or {}
  headers["Content-Type"] = "application/json"
  local res = assert(client:send{
    method = "POST",
    path = path,
    body = body or {},
    headers = headers
  })
  return cjson.decode(assert.res_status(expected_status or 201, res))
end


local function patch(path, body, headers, expected_status)
  headers = headers or {}
  headers["Content-Type"] = "application/json"
  local res = assert(client:send{
    method = "PATCH",
    path = path,
    body = body or {},
    headers = headers
  })
  return cjson.decode(assert.res_status(expected_status or 200, res))
end


local function put(path, body, headers, expected_status)
  headers = headers or {}
  headers["Content-Type"] = "application/json"
  local res = assert(client:send{
    method = "PUT",
    path = path,
    body = body or {},
    headers = headers
  })
  return cjson.decode(assert.res_status(expected_status or 202, res))
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

local function delete(path, headers, expected_status)
  headers = headers or {}
  headers["Content-Type"] = "application/json"
  local res = assert(client:send{
    method = "DELETE",
    path = path,
    headers = headers
  })
  assert.res_status(expected_status or 204, res)
end


local function create_api(suffix)
  suffix = tostring(suffix)
  return post("/apis", {
    uris = "/my-uri" .. suffix,
    name = "my-api" .. suffix,
    methods = "GET",
    hosts = "my.api" .. suffix ..".com",
    upstream_url = "http://api".. suffix.. ".com"})
end

local function map(pred, t)
  local r = {}
  for i, v in ipairs(t) do
    r[i] = pred(v)
  end
  return r
end


-- workaround since dao.rbac_roles:find_all({ name = role_name }) returns nothing
local function find_role(dao, role_name)
  local res, err = dao.rbac_roles:find_all()
  if err then
    return nil, err
  end

  for _, role in ipairs(res) do
    if role.name == role_name then
      return role
    end
  end
end


dao_helpers.for_each_dao(function(kong_config)

describe("Admin API RBAC with #" .. kong_config.database, function()
  local bp, dao, _

  setup(function()
    bp,_,dao = helpers.get_db_utils(kong_config.database)
    dao:drop_schema()
    ngx.ctx.workspaces = {}
    dao:run_migrations()

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
        assert.matches("%$2b%$09%$", json.user_token)
        assert.equal("bar", json.comment)
        assert.is_true(utils.is_valid_uuid(json.id))
        assert.is_true(json.enabled)
      end)

      it("creates a new user with a corresponding default role", function()
        local res = assert(client:send {
          method = "POST",
          path = "/rbac/users",
          body = {
            name = "fubar",
            user_token = "fubarfu",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.equal("fubar", json.name)
        assert.matches("%$2b%$09%$", json.user_token)

        -- what I really want to do here is :find_all({ name = "fubar" }),
        -- but that doesn't return any results
        local role = find_role(dao, "fubar")
        assert.not_nil(role)
        assert.is_true(role.is_default)
      end)

      it("creates a new user with existing role as default role", function()
        local res

        -- create a role with a very-likely-to-colide name
        res = assert(client:send {
          method = "POST",
          path = "/rbac/roles",
          body = {
            name = "rbacy",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        assert.res_status(201, res)

        -- create a user with this same very-likely-to-colide name
        res = assert(client:send {
          method = "POST",
          path = "/rbac/users",
          body = {
            name = "rbacy",
            user_token = "rbacelicius",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        assert.res_status(201, res)

        -- make sure the user is in fact in that role!
        res = assert(client:send {
          method = "GET",
          path = "/rbac/users/rbacy/roles",
        })

        local roles = assert.res_status(200, res)
        local roles_json = cjson.decode(roles)

        assert(1, #roles_json.roles)
        assert.equal("rbacy", roles_json.roles[1].name)

        -- cleanup
        res = assert(client:send {
          method = "DELETE",
          path = "/rbac/users/rbacy",
        })
        assert.res_status(204, res)

        -- role is gone too!
        res = assert(client:send {
          method = "GET",
          path = "/rbac/roles/rbacy",
        })
        assert.res_status(404, res)
      end)

      it("doesn't delete default role if it is shared", function()
        local res

        -- create a user with some very-likely-to-colide name
        res = assert(client:send {
          method = "POST",
          path = "/rbac/users",
          body = {
            name = "rbacy",
            user_token = "rbacelicius",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        local body = assert.res_status(201, res)
        local rbacy_user = cjson.decode(body)

        -- make sure rbacy_user has rbacy_role
        local rbacy_role = find_role(dao, "rbacy")
        local user_roles = dao.rbac_user_roles:find_all({ user_id = rbacy_user.id, role_id = rbacy_role.id })
        assert.same(rbacy_role.id, user_roles[1].role_id)

        -- now, create another user who will have rbacy role
        -- note that is to support legacy situation where default role
        -- used to be exposed in the Admin API
        res = assert(client:send {
          method = "POST",
          path = "/rbac/users",
          body = {
            name = "yarbacy",
            user_token = "yarbacelicius",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        local body = assert.res_status(201, res)
        local yarbacy_user = cjson.decode(body)

        assert(dao.rbac_user_roles:insert({ user_id = yarbacy_user.id, role_id = rbacy_role.id }))

        -- delete the rbacy user
        res = assert(client:send {
          method = "DELETE",
          path = "/rbac/users/rbacy",
        })
        assert.res_status(204, res)

        -- and check the rbacy role is still here, as yarbacy
        -- still has the rbacy role and would hate to lose it
        local user_roles = dao.rbac_user_roles:find_all({ user_id = yarbacy_user.id, role_id = rbacy_role.id })
        assert.equal(rbacy_role.id, user_roles[1].role_id)

        -- clean up user and role
        -- note we never get here if an assertion above fails
        res = assert(client:send {
          method = "DELETE",
          path = "/rbac/users/yarbacy",
        })
        assert.res_status(204, res)
        dao.rbac_roles:delete({ id = rbacy_role.id })
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
        assert.matches("%$2b%$09%$", json.user_token)
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

          assert.res_status(400, res)
        end)

        it("with duplicate names", function()
          local res = assert(client:send {
            method = "POST",
            path = "/rbac/users",
            body = {
              name = "jerry",
              user_token = "woodohwee",
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
              user_token = "woodohwoo",
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

        assert.equals(5, #json.data)
      end)

      pending("lists enabled users", function()
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/users",
          query = {
            enabled = true,
          },
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals(4, #json.data)
      end)

      it("filters out admins", function()
        ee_helpers.create_admin("gruce-admin@konghq.com", nil, 0, bp, dao)

        local res = assert(client:send {
          method = "GET",
          path = "/rbac/users/"
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        for _, user in ipairs(json.data) do
          assert.are_not.same("gruce-admin@konghq.com", user.name)
        end
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

      it("returns 404 for an rbac_user associated to an admin", function()
        local admin = ee_helpers.create_admin("gruce@konghq.com", nil, 0, bp, dao)

        local res = assert(client:send {
          method = "GET",
          path = "/rbac/users/" .. admin.rbac_user.id,
        })

        assert.res_status(404, res)
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

          local name = utils.uuid()
          post("/rbac/roles", { name = name })
          post("/rbac/roles", { name = name }, nil, 409)
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

        assert.equals(7, #json.data)
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

        assert.is_nil(find_role(dao, "baz"))
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

        -- bob has read-only now
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

        -- jerry now has read-only and admin
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
      it("displays the public (non-default) roles associated with the user", function()
        local res = assert(client:send {
          path = "/rbac/users/bob/roles",
          method = "GET",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        -- bob has read-only role
        assert.same(1, #json.roles)
        assert.same("read-only", json.roles[1].name)
        assert.same("bob", json.user.name)

        res = assert(client:send {
          path = "/rbac/users/jerry/roles",
          method = "GET",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        -- jerry has admin and read-only
        assert.same(2, #json.roles)
        local names = map(function(x) return x.name end , json.roles)
        assert.contains("admin", names)
        assert.contains("read-only", names)
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

        -- bob didn't have any other public roles
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

        -- jerry no longer has read-only
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
      ngx.ctx.workspaces = {}
      dao:run_migrations()
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

      res = assert(client:send {
        path = "/rbac/roles/super-admin/entities/permissions",
        method = "GET",
      })

      body = assert.res_status(200, res)
      assert.matches("*", body, nil, true)
      assert.matches("delete", body, nil, true)
      assert.matches("create", body, nil, true)
      assert.matches("update", body, nil, true)
      assert.matches("read", body, nil, true)
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
          user_token = "valhalla",
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

      assert.res_status(201, res)

      res = assert(client:send {
        method = "GET",
        path = "/rbac/users/bob/permissions",
      })

      assert.res_status(200, res)

      -- TODO test permissions

      -- this is jerry
      -- jerry can view, create, update, and delete most resources
      local res = assert(client:send {
        method = "POST",
        path = "/rbac/users",
        body = {
          name = "jerry",
          user_token = "basilexposition",
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

      assert.res_status(201, res)

      res = assert(client:send {
        method = "GET",
        path = "/rbac/users/jerry/permissions",
      })

      assert.res_status(200, res)

      -- TODO test decoded permissions

      -- this is alice
      -- alice can do whatever the hell she wants
      local res = assert(client:send {
        method = "POST",
        path = "/rbac/users",
        body = {
          name = "alice",
          user_token = "deliciousmerangue",
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

      assert.res_status(201, res)
      res = assert(client:send {
        method = "GET",
        path = "/rbac/users/alice/permissions",
      })

      assert.res_status(200, res)

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
          user_token = "expecto patronum",
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

      assert.res_status(201, res)

      res = assert(client:send {
        method = "GET",
        path = "/rbac/users/herb/permissions",
      })

      assert.res_status(200, res)
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
        assert.same(2, dao.rbac_role_entities:count())
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

        assert.res_status(200, res)
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
            endpoint = "/foo",
            actions = "*",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.same("mock-workspace", json.workspace)
        assert.same("/foo", json.endpoint)

        table.sort(json.actions)
        assert.same({ "create", "delete", "read", "update" }, json.actions)
        assert.is_false(json.negative)
        assert.is_nil(json.comment)
      end)

      it("creates a new * endpoint with similar PK elements", function()
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

      it("creates a new / endpoint with similar PK elements", function()
        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/mock-role/endpoints",
          body = {
            workspace = "mock-workspace",
            endpoint = "/",
            actions = "read",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.same("mock-workspace", json.workspace)
        assert.same("/", json.endpoint)

        assert.same({ "read" }, json.actions)
        assert.is_false(json.negative)
        assert.is_nil(json.comment)
      end)

      it("new endpoint's workspace defaults to the current request's workspace", function()
        post("/workspaces", {name = "ws123"})
        post("/ws123/rbac/roles", {name = "ws123-admin"})
        local perm = post("/ws123/rbac/roles/ws123-admin/endpoints",
          {actions = "*", endpoint="*"})
        assert.same({ "delete", "create", "update", "read" }, perm.actions)
        assert.same("*", perm.endpoint)
        assert.is_false(perm.negative)
        assert.same("ws123", perm.workspace)
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
              endpoint = "/foo",
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
              endpoint = "/foo",
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
              endpoint = "/foo",
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

        assert.same(3, json.total)
        assert.same(3, #json.data)
      end)

      it("limits the size of returned entities", function()
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/roles/mock-role/endpoints?size=1",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same(3, json.total)
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
        assert.equals("/foo", json.endpoint)

        table.sort(json.actions)
        assert.same({ "create", "delete", "read", "update" }, json.actions)
      end)

      -- this is the limitation of lapis implementation
      -- it's not possible to distinguish // from /
      -- since the self.params.splat will always be "/"
      it("treats /rbac/roles/:name_or_id/endpoints/:workspace// as /rbac/roles/:name_or_id/endpoints/:workspace/", function()
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/roles/mock-role/endpoints/mock-workspace//",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals("mock-workspace", json.workspace)
        assert.equals("/", json.endpoint)

        table.sort(json.actions)
        assert.same({ "read" }, json.actions)
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

      it("updates * endpoint properly", function()
        local res = assert(client:send {
          method = "PATCH",
          path = "/rbac/roles/mock-role/endpoints/mock-workspace/*",
          body = {
            comment = "fooo",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.is_true(utils.is_valid_uuid(json.role_id))
        assert.same("fooo", json.comment)
        table.sort(json.actions)
        assert.same({ "read" }, json.actions)
      end)

      it("updates / endpoint properly", function()
        local res = assert(client:send {
          method = "PATCH",
          path = "/rbac/roles/mock-role/endpoints/mock-workspace/",
          body = {
            comment = "foooo",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.is_true(utils.is_valid_uuid(json.role_id))
        assert.same("foooo", json.comment)
        table.sort(json.actions)
        assert.same({ "read" }, json.actions)
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

      it("update the relationship actions and displays them properly for * endpoint", function()
        local res = assert(client:send {
          method = "PATCH",
          path = "/rbac/roles/mock-role/endpoints/mock-workspace/*",
          body = {
            actions = "read,update,delete",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same("fooo", json.comment)

        table.sort(json.actions)
        assert.same({ "delete", "read", "update" }, json.actions)
      end)

      it("update the relationship actions and displays them properly for / endpoint", function()
        local res = assert(client:send {
          method = "PATCH",
          path = "/rbac/roles/mock-role/endpoints/mock-workspace/",
          body = {
            actions = "read,update,delete",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same("foooo", json.comment)

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
        assert.same(2, dao.rbac_role_entities:count())
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

      it("removes * endpoint association", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/rbac/roles/mock-role/endpoints/mock-workspace/*",
        })

        assert.res_status(204, res)
        -- TODO review dao calls in this file - workspaces/rbac
        -- dao integration has rough edges
        --
        -- 2 due to the new super-admin default * entity permission
        assert.same(2, dao.rbac_role_entities:count())
      end)

      it("removes / endpoint association", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/rbac/roles/mock-role/endpoints/mock-workspace/",
        })

        assert.res_status(204, res)
        -- TODO review dao calls in this file - workspaces/rbac
        -- dao integration has rough edges
        --
        -- 2 due to the new super-admin default * entity permission
        assert.same(2, dao.rbac_role_entities:count())
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

  describe("/rbac/users/consumers map with " .. kong_config.database, function()
    local client
    local user_consumer_map
    local bp
    local dao
    local consumer

    setup(function()
      helpers.stop_kong()

      local _
      bp, _, dao = helpers.get_db_utils(kong_config.database)

      assert(helpers.start_kong({
        database = kong_config.database
      }))

      consumer = bp.consumers:insert { username = "dale" }
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

      dao:truncate_tables()
      helpers.stop_kong()
    end)

    describe("POST", function()
      it("creates a consumer user map", function()

        local user = dao.rbac_users:insert {
          name = "the-dale-user",
          user_token = "letmein",
          enabled = true,
        }

        local res = assert(client:send {
          method = "POST",
          path = "/rbac/users/consumers",
          body = {
            user_id = user.id,
            consumer_id = consumer.id
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        local body = assert.res_status(201, res)
        user_consumer_map = cjson.decode(body)

        assert.equal(user_consumer_map.user_id, user.id)
        assert.equal(user_consumer_map.consumer_id, consumer.id)
      end)
    end)

    describe("GET", function()
      it("retrieves a specific consumer user map", function()
        local res = assert(client:send {
          method = "GET",
          path = "/rbac/users/" .. user_consumer_map.user_id .."/consumers/"
                 .. user_consumer_map.consumer_id,
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same(json, user_consumer_map)
      end)
    end)
  end)
end)

for _, h in ipairs({ "", "Custom-Auth-Token" }) do
  describe("Admin API", function()
    local client
    local expected = h == "" and "Kong-Admin-Token" or h

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

    it("defaults Access-Control-Allow-Origin to *", function()
      local res = assert(client:send {
        method = "OPTIONS",
        path   = "/",
      })

      assert.res_status(204, res)
      assert.same("*", res.headers["Access-Control-Allow-Origin"])
    end)
  end)
end


dao_helpers.for_each_dao(function(kong_config)
describe("Admin API", function()
  local apis

  setup(function()
    helpers.get_db_utils(kong_config.database)

    assert(helpers.start_kong({
      database = kong_config.database,
    }))
    client = assert(helpers.admin_client("127.0.0.1", 8001))

    apis = map(create_api, {1, 2, 3, 4})

    post("/rbac/users", {name = "bob", user_token = "bob"})
    post("/rbac/roles" , {name = "mock-role"})
    post("/rbac/roles/mock-role/entities", {entity_id = apis[2].id, actions = "read"})
    post("/rbac/roles/mock-role/entities", {entity_id = apis[3].id, actions = "delete"})
    post("/rbac/roles/mock-role/entities", {entity_id = apis[4].id, actions = "update"})
    post("/rbac/users/bob/roles", {roles = "mock-role"})

    helpers.stop_kong(nil, true, true)
    assert(helpers.start_kong {
      database              = kong_config.database,
      enforce_rbac          = "entity",
    })
    client = assert(helpers.admin_client())
  end)

  teardown(function()
    helpers.stop_kong()

    if client then
      client:close()
    end
  end)

  it(".find_all filters non accessible entities", function()
    local data = get("/apis", {["Kong-Admin-User"] = "bob",
                               ["Kong-Admin-Token"] = "bob"}).data
    assert.equal(1, #data)
    assert.equal(apis[2].id, data[1].id)
  end)

  it(".find_all returns 401 for invalid credentials", function()
    get("/apis", {["Kong-Admin-Token"] = "wrong"}, 401)
    get("/apis", nil, 401)
  end)

  it(".find errors for non permitted entities", function()
    get("/apis/" .. apis[1].id , {["Kong-Admin-Token"] = "wrong"}, 401)
    get("/apis/" .. apis[2].id , {["Kong-Admin-Token"] = "wrong"}, 401)
    get("/apis/" .. apis[1].id , {["Kong-Admin-Token"] = "bob"}, 404)
    get("/apis/" .. apis[2].id , {["Kong-Admin-Token"] = "bob"}, 200)
  end)

  it(".update checks rbac via put", function()
    put("/apis/" , {
      id = apis[1].id,
      name = "new-name",
      created_at = "123",
      upstream_url = helpers.mock_upstream_url,
    }, {["Kong-Admin-Token"] = "bob"}, 403)

    put("/apis/" , {
      id = apis[4].id,
      name = "new-name",
      created_at = "123",
      upstream_url = helpers.mock_upstream_url
    }, {["Kong-Admin-Token"] = "bob"}, 200)
  end)

  it(".update checks rbac via patch", function()
    patch("/apis/".. apis[1].id, {name = "new-name"}, {["Kong-Admin-Token"] = "bob" }, 404)
    patch("/apis/".. apis[2].id, {name = "new-name"}, {["Kong-Admin-Token"] = "bob" }, 404)
    patch("/apis/".. apis[3].id, {name = "new-name"}, {["Kong-Admin-Token"] = "bob" }, 404)
    patch("/apis/".. apis[4].id, {name = "new-name"}, {["Kong-Admin-Token"] = "bob" }, 200)
  end)

  it(".delete checks rbac", function()
    delete("/apis/" .. apis[1].id, nil, 401)
    delete("/apis/" .. apis[2].id, nil, 401)
    delete("/apis/" .. apis[1].id, {["Kong-Admin-Token"] = "bob" }, 404)
    delete("/apis/" .. apis[2].id, {["Kong-Admin-Token"] = "bob" }, 404)
    delete("/apis/" .. apis[3].id, {["Kong-Admin-Token"] = "bob" }, 204)
  end)
end)

end)

dao_helpers.for_each_dao(function(kong_config)
describe("RBAC users", function()
  local dao, _
  setup(function()
    _,_,dao = helpers.get_db_utils(kong_config.database)

    assert(helpers.start_kong({
      database = kong_config.database,
    }))
    client = assert(helpers.admin_client("127.0.0.1", 8001))
    dao:run_migrations()

    -- create 2 workspaces
    post("/workspaces", {name = "ws1"})
    post("/workspaces", {name = "ws2"})

    -- user 'admin' (role ws1ws2-admin) has powers over both
    post("/ws1/rbac/users", {name = "admin", user_token = "ws1ws2-admin"})
    post("/ws1/rbac/roles" , {name = "ws1ws2-admin"})
    post("/ws1/rbac/roles/ws1ws2-admin/endpoints", {endpoint = "*", actions = "*", workspace = "ws2"})
    post("/ws1/rbac/roles/ws1ws2-admin/endpoints", {endpoint = "*", actions = "*", workspace = "ws1"})
    post("/ws1/rbac/users/admin/roles", {roles = "ws1ws2-admin"})

    -- user bob (role ws1-admin) has only powers over ws1
    post("/ws1/rbac/users", {name = "bob", user_token = "bob"})
    post("/ws1/rbac/roles" , {name = "ws1-admin"})
    post("/ws1/rbac/roles/ws1-admin/endpoints", {endpoint = "*", actions = "read,create,update,delete", workspace = "ws1"})
    post("/ws1/rbac/users/bob/roles", {roles = "ws1-admin"})

    helpers.stop_kong(nil, true, true)
    assert(helpers.start_kong {
      database              = kong_config.database,
      enforce_rbac          = "on",
    })
    client = assert(helpers.admin_client())
  end)

  teardown(function()
    helpers.stop_kong(nil, true, true)

    if client then
      client:close()
    end
  end)

  it("cannot give permissions to workspaces they do not manage", function()
    post("/ws1/rbac/roles/ws1-admin/endpoints", {
      endpoint = "*",
      workspace = "ws2",
      actions = "read,create,update,delete"},
        {["Kong-Admin-Token"] = "bob"}, 403)
  end)

  it("can give permissions to the same workspace of the request", function()
    post("/ws1/rbac/roles/ws1-admin/endpoints", {
      endpoint = "/bla",
      workspace = "ws1",
      actions = "read,create,update,delete"},
        {["Kong-Admin-Token"] = "bob"}, 201)
  end)

  it("can give permissions to other workspaces if they manage", function()
    post("/ws1/rbac/roles/ws1-admin/endpoints", {
      endpoint = "*",
      workspace = "ws2",
      actions = "read,create,update,delete"},
        {["Kong-Admin-Token"] = "ws1ws2-admin"}, 201)
  end)

end)
end)
