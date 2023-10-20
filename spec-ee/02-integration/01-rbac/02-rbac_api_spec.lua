-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"
local ee_helpers = require "spec-ee.helpers"
local pl_file = require "pl.file"
local constants = require "kong.constants"
local escape_uri = ngx.escape_uri
local clear_license_env = require("spec-ee.helpers").clear_license_env
local get_portal_and_vitals_key = require("spec-ee.helpers").get_portal_and_vitals_key


local PORTAL_PREFIX = constants.PORTAL_PREFIX
local null = ngx.null


local compare_no_order = require "pl.tablex".compare_no_order

local client
local another_client


local function post(path, body, headers, expected_status, expected_body)
  headers = headers or {}
  headers["Content-Type"] = "application/json"
  local res = assert(client:send{
    method = "POST",
    path = path,
    body = body or {},
    headers = headers
  })
  if expected_body then
    assert.matches(expected_body, res:read_body(), nil, true)
  end
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

local function put(path, body, headers, expected_status) -- luacheck: ignore
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


local function create_service(suffix)
  suffix = tostring(suffix)
  return post("/services", {
    name = "my-service" .. suffix,
    host = "my-service-host-" .. suffix,
  })
end

local function map(pred, t)
  local r = {}
  for i, v in ipairs(t) do
    r[i] = pred(v)
  end
  return r
end


-- workaround since dao.rbac_roles:find_all({ name = role_name }) returns nothing
local function find_role(db, role_name)
  for role, err in db.rbac_roles:each() do
    if role.name == role_name then
      return role
    end
    if err then
      return nil, err
    end
  end
end


for _, strategy in helpers.each_strategy() do

describe("Admin API RBAC with #" .. strategy, function()
  local bp, db
  local reset_license_data

  lazy_setup(function()
    reset_license_data = clear_license_env()
    bp, db = helpers.get_db_utils(strategy)

    assert(helpers.start_kong({
      database = strategy,
      portal = true,
      portal_and_vitals_key = get_portal_and_vitals_key(),
      portal_auth = "basic-auth",
      portal_session_conf = "{ \"secret\": \"super-secret\", \"cookie_secure\": false }",
      license_path = "spec-ee/fixtures/mock_license.json",
    }))

    bp.workspaces:insert({ name = "mock-workspace" })

    bp.workspaces:insert({
      name = "portal-enabled-workspace",
      config =  {
        portal = true,
      },
    })
  end)

  before_each(function()
    db:truncate("rbac_users")
    db:truncate("rbac_user_roles")
    db:truncate("rbac_roles")
    db:truncate("rbac_role_entities")
    db:truncate("rbac_role_endpoints")
    db:truncate("developers")
    db:truncate("consumers")
    db:truncate("basicauth_credentials")

    if client then
      client:close()
    end
    if another_client then
      another_client:close()
    end

    client = assert(helpers.admin_client())
    another_client = assert(helpers.admin_client())
  end)

  lazy_teardown(function()
    if client then
      client:close()
    end
    if another_client then
      another_client:close()
    end

    helpers.stop_kong()
    reset_license_data()
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
        local role = find_role(db, "fubar")
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

      it("does not delete default role if it is shared", function()
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
        local rbacy_role = find_role(db, "rbacy")
        local user_roles = db.rbac_user_roles:select({
          user = rbacy_user,
          role = rbacy_role,
        })

        assert.same(rbacy_role.id, user_roles.role.id)

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

        assert(db.rbac_user_roles:insert({
          user = yarbacy_user,
          role = rbacy_role,
        }))

        -- delete the rbacy user
        res = assert(client:send {
          method = "DELETE",
          path = "/rbac/users/rbacy",
        })
        assert.res_status(204, res)

        -- and check the rbacy role is still here, as yarbacy
        -- still has the rbacy role and would hate to lose it
        local user_role = db.rbac_user_roles:select({
          user = yarbacy_user,
          role = rbacy_role,
        })
        assert.equal(rbacy_role.id, user_role.role.id)

        -- clean up user and role
        -- note we never get here if an assertion above fails
        res = assert(client:send {
          method = "DELETE",
          path = "/rbac/users/yarbacy",
        })
        assert.res_status(204, res)
        db.rbac_roles:delete({ id = rbacy_role.id })
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
      it("returns the right data structure when empty", function()
        local res = assert(client:get("/rbac/users"))
        local body = assert.res_status(200, res)

        assert.matches('"next":null', body, nil, true)
        assert.matches('"data":[]', body, nil, true)
      end)

      it("lists users", function()
        local res = assert(client:post("/rbac/users", {
          body = {
            name = "jerry",
            user_token = "foo",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        }))

        assert.res_status(201, res)

        local res = assert(client:send {
          method = "GET",
          path = "/rbac/users",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equals(1, #json.data)
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
        local email = "gruceadmin@konghq.com"

        local admin = ee_helpers.create_admin(email, nil, 0, db)

        local res = assert(client:send {
          method = "GET",
          path = "/rbac/users/"
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        for _, user in ipairs(json.data) do
          assert.not_equal(admin.rbac_user.id, user.id)
        end
      end)

      it("filters out developers", function()
        local res = assert(client:send {
          method = "POST",
          path = "/portal-enabled-workspace/developers/roles",
          body = {
            name = "test_role",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        assert.res_status(201, res)

        local res = assert(client:send {
          method = "POST",
          path = "/portal-enabled-workspace/developers",
          body = {
            email = "test_dev@konghq.com",
            password = "kong",
            meta = "{\"full_name\":\"I Like Turtles\"}",
            roles = { "test_role" }
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        local developer = json

        local res = assert(client:send {
          method = "GET",
          path = "/portal-enabled-workspace/rbac/users"
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        for _, user in ipairs(json.data) do
          assert.not_equal(developer.rbac_user.id, user.id)
        end
      end)
    end)
  end)

  describe("/rbac/users/:name_or_id", function()
    local user1, user2

    describe("GET", function()
      it("retrieves a specific user by name and id", function()
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
        assert.res_status(201, res)

        local res = assert(client:send {
          method = "GET",
          path = "/rbac/users/bob",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        user1 = json

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
        local admin = ee_helpers.create_admin("global@konghq.com", nil, 0, db)

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
        assert.res_status(201, res)

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

      it("rehashes user_token when updating a user with a non-bcrypt digest-like token", function()
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
        local rbac_user = cjson.decode(body)

        res = assert(client:send {
          method = "PATCH",
          path = "/rbac/users/bob",
          body = {
            user_token = "bar",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.matches("%$2b%$09%$", json.user_token)
        assert.not_equal(rbac_user.user_token, json.user_token)
      end)

      it("doesn't rehash user_token when updating a user with a bcrypt digest-like token", function()
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
        local rbac_user = cjson.decode(body)
        local new_user_token = rbac_user.user_token

        if string.sub(new_user_token, -4) == "AaaA" then
          new_user_token = string.sub(new_user_token, 1, -5) .. "aAAa"
        else
          new_user_token =  string.sub(new_user_token, 1, -5) .. "AaaA"
        end

        res = assert(client:send {
          method = "PATCH",
          path = "/rbac/users/bob",
          body = {
            user_token = new_user_token,
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })

        body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equal(new_user_token, json.user_token)
      end)

    end)

    describe("DELETE", function()
      it("deletes a given user", function()
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
        assert.res_status(201, res)

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

          assert.res_status(400, res)
        end)
      end)
    end)

    describe("GET", function()
      it("returns the right data structure when empty", function()
        local res = assert(client:get("/rbac/roles"))
        local body = assert.res_status(200, res)

        assert.matches('"next":null', body, nil, true)
        assert.matches('"data":[]', body, nil, true)
      end)

      it("lists roles", function()
        local id = utils.uuid()
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

        local res = assert(client:send {
          method = "GET",
          path = "/rbac/roles",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.not_equal(0, #json.data)
      end)

      it("filters out portal roles", function()
        local regular_role = post("/portal-enabled-workspace/rbac/roles", {
          name = "regular_rbac_role",
        }, nil, 201)

        -- generate more portal rows than page size
        -- this will test filtering of portal rows
        -- where the valid roles are beyond the first page of results
        for i = 1, 10 do
          post("/portal-enabled-workspace/developers/roles", {
            name = "portal_role_" .. i,
          }, nil, 201)
        end

        local res = get("/portal-enabled-workspace/rbac/roles?size=3", nil, 200)

        assert.equals(1, #res.data)
        assert.equals(regular_role.id, res.data[1].id)
      end)

      it("returns empty - filtering portal roles < page size", function()
        for i = 1, 10 do
          post("/portal-enabled-workspace/developers/roles", {
            name = "portal_role_" .. i,
          }, nil, 201)
        end

        local res = get("/portal-enabled-workspace/rbac/roles?size=20", nil, 200)

        assert.equals(null, res.next)
        assert.equals(0, #res.data)
      end)

      it("returns empty - filtering portal roles == page size", function()
        for i = 1, 10 do
          post("/portal-enabled-workspace/developers/roles", {
            name = "portal_role_" .. i,
          }, nil, 201)
        end

        local res = get("/portal-enabled-workspace/rbac/roles?size=10", nil, 200)

        assert.equals(null, res.next)
        assert.equals(0, #res.data)
      end)

      it("returns empty - filtering portal roles > page size", function()
        for i = 1, 10 do
          post("/portal-enabled-workspace/developers/roles", {
            name = "portal_role_" .. i,
          }, nil, 201)
        end

        local res = get("/portal-enabled-workspace/rbac/roles?size=3", nil, 200)

        assert.equals(null, res.next)
        assert.equals(0, #res.data)
      end)

      it("paginates", function()
        for i = 1, 25 do
          post("/portal-enabled-workspace/rbac/roles", {
            name = "regular_rbac_role_".. i,
          }, nil, 201)

          post("/portal-enabled-workspace/developers/roles", {
            name = "portal_role_" .. i,
          }, nil, 201)
        end

        local res = get("/portal-enabled-workspace/rbac/roles?size=10", nil, 200)

        assert.equals(10, #res.data)

        local res = get("/portal-enabled-workspace" .. res.next .. "&size=10", nil, 200)

        assert.equals(10, #res.data)

        local res = get("/portal-enabled-workspace" .. res.next .. "&size=10", nil, 200)

        assert.equals(5, #res.data)
        assert.equals(null, res.next)
      end)

      it('logs a warning when exiting after 1000 iterations', function()
        local err_log = pl_file.read(helpers.test_conf.nginx_err_logs)
        assert.not_matches("unable to retrieve full page of rbac_roles after 1000 iterations",
                       err_log, nil, true)

        for i = 1, 1001 do
          bp.rbac_roles:insert({
            name = PORTAL_PREFIX .. "portal_role_" .. i,
          })
        end

        get("/rbac/roles?size=1", nil, 200)

        local err_log = pl_file.read(helpers.test_conf.nginx_err_logs)
        assert.matches("unable to retrieve full page of rbac_roles after 1000 iterations",
                       err_log, nil, true)
      end)
    end)
  end)

  describe("/rbac/roles/:name_or_id", function()
    describe("GET", function()
      it("retrieves a specific role by name", function()
        local role1, role2

        local res = assert(client:post("/rbac/roles", {
          body = {
            name = "role-123",
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(201, res)

        local res = assert(client:send {
          method = "GET",
          path = "/rbac/roles/role-123",
        })
        local body = assert.res_status(200, res)
        role1 = cjson.decode(body)

        local res = assert(client:send {
          method = "GET",
          path = "/rbac/roles/" .. role1.id,
        })

        local body = assert.res_status(200, res)
        role2 = cjson.decode(body)

        assert.same(role1, role2)
      end)
    end)

    describe("PATCH", function()
      it("updates a specific role", function()
        local role1, role2

        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles",
          body = {
            name = "read-only",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        local body = assert.res_status(201, res)
        role1 = cjson.decode(body)

        res = assert(client:send {
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
        role2 = cjson.decode(body)

        assert.equals("new comment", role2.comment)
        assert.not_equals(role1.comment, role2.comment)
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
          method = "POST",
          path = "/rbac/roles",
          body = {
            name = "baz",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, res)

        local res = assert(client:send {
          method = "DELETE",
          path = "/rbac/roles/baz",
        })

        assert.res_status(204, res)
        assert.is_nil(find_role(db, "baz"))
      end)
      describe("errors", function()
        it("when the role doesn't exist", function()
          delete("/rbac/roles/notexists", nil, 204)
        end)
      end)

    end)
  end)

  describe("/rbac/users/:name_or_id/roles", function()
    describe("POST", function()
      it("associates a role with a user", function()
        local res = assert(client:send {
          method = "POST",
          path = "/rbac/users",
          body = {
            name = "bob",
            user_token = "boboken",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, res)

        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles",
          body = {
            name = "read-only",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, res)

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
          path = "/rbac/users",
          method = "POST",
          body = {
            name = "jerry",
            user_token = "jerroken",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, res)

        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles",
          body = {
            name = "read-only",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, res)

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
            path = "/rbac/users",
            method = "POST",
            body = {
              name = "bob",
              user_token = "boboken",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })
          assert.res_status(201, res)

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

        it("when duplicate relationships are attempted", function()
          local res = assert(client:send {
            path = "/rbac/users",
            method = "POST",
            body = {
              name = "bill",
              user_token = "boboken",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })
          assert.res_status(201, res)

          local res = assert(client:send {
            method = "POST",
            path = "/rbac/roles",
           body = {
              name = "read-only",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })
          assert.res_status(201, res)

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

          assert.res_status(400, res)
        end)
      end)
    end)

    describe("GET", function()
      it("displays the public (non-default) roles associated with the user", function()
        local res = assert(client:send {
          path = "/rbac/users",
          method = "POST",
          body = {
            name = "bob",
            user_token = "boboken",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, res)

        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles",
          body = {
            name = "read-only",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, res)

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
        assert.res_status(201, res)

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

        local res = assert(client:send {
          path = "/rbac/users",
          method = "POST",
          body = {
            name = "jerry",
            user_token = "jerroken",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, res)

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
        assert.res_status(201, res)

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
          path = "/rbac/users",
          method = "POST",
          body = {
            name = "bob",
            user_token = "boboken",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, res)

        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles",
          body = {
            name = "read-only",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, res)

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
        assert.res_status(201, res)

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
          method = "POST",
          path = "/rbac/roles",
          body = {
            name = "read-only",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, res)

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

        local res = assert(client:send {
          path = "/rbac/users",
          method = "POST",
          body = {
            name = "jerry",
            user_token = "jerroken",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, res)

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
        assert.res_status(201, res)

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
            path = "/rbac/users",
            method = "POST",
            body = {
              name = "bob",
              user_token = "boboken",
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })
          assert.res_status(201, res)

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
          method = "POST",
          path = "/rbac/roles",
          body = {
            name = "read-only",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, res)

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

  -- TODO seed data not yet available in migrations
  describe("rbac defaults ", function()
    lazy_setup(function()
      -- db, dao = helpers.get_db_utils(strategy)
      ee_helpers.register_rbac_resources(db)
    end)

    before_each(function()
      ee_helpers.register_rbac_resources(db)
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

      -- check multiple call on rbac endpoint should return the same result
      res = assert(another_client:send {
        path = "/rbac/roles/super-admin/endpoints/permissions",
        method = "GET",
      })

      body = assert.res_status(200, res)
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

  describe("/rbac/roles/:name_or_id/entities", function()
    describe("POST", function()
      it("associates an entity with a role", function()
        local e_id
        local res, body, json

        -- create some entity
        res = assert(client:send {
          method = "POST",
          path = "/consumers",
          body = {
            username = "c135",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        body = assert.res_status(201, res)
        json = cjson.decode(body)

        -- save the entity's id
        e_id = json.id

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

        -- entity_type must be valid
        res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/mock-role/entities",
          body = {
            entity_id = e_id,
            entity_type = "services", -- incorrect
            actions = "read",
          },
          headers = {
            ["Content-Type"] = "application/json"
          },
        })
        assert.res_status(400, res)

        -- entity_type must be valid
        res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/mock-role/entities",
          body = {
            entity_id = e_id,
            entity_type = "test", -- incorrect
            actions = "read",
          },
          headers = {
            ["Content-Type"] = "application/json"
          },
        })
        assert.res_status(400, res)

        res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/mock-role/entities",
          body = {
            entity_id = e_id,
            entity_type = "consumers",
            actions = "read",
          },
          headers = {
            ["Content-Type"] = "application/json"
          },
        })

        body = assert.res_status(201, res)
        json = cjson.decode(body)

        assert.equals(json.entity_id, e_id)
        assert.is_false(json.negative)
        assert.equals("consumers", json.entity_type)
      end)

      it("detects an entity as a workspace", function()
        -- create a workspace
        local res = assert(client:send {
          method = "POST",
          path = "/workspaces",
          body = {
            name = "ws123",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        local w_id = json.id

        local res = assert(client:send {
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

        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/mock-role/entities",
          body = {
            entity_id = w_id,
            entity_type = "workspaces",
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
          -- create a workspace
          local res = assert(client:send {
            method = "POST",
            path = "/workspaces",
            body = {
              name = "ws1379",
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          local w_id = json.id

          local res = assert(client:send {
            method = "POST",
            path = "/rbac/roles/dne-role/entities",
            body = {
              entity_id = w_id,
              entity_type = "workspaces",
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
        local e_id, w_id
        local res, body, json

        -- create some entity
        res = assert(client:send {
          method = "POST",
          path = "/consumers",
          body = {
            username = "c19",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        body = assert.res_status(201, res)
        json = cjson.decode(body)

        -- save the entity's id
        e_id = json.id

        res = assert(client:send {
          method = "POST",
          path = "/consumers",
          body = {
            username = "c1234",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        body = assert.res_status(201, res)
        json = cjson.decode(body)
        w_id = json.id

        local res = assert(client:send {
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
            entity_type = "consumers",
            actions = "read",
          },
          headers = {
            ["Content-Type"] = "application/json"
          },
        })
        assert.res_status(201, res)

        res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/mock-role/entities",
          body = {
            entity_id = w_id,
            entity_type = "consumers",
            actions = "read",
          },
          headers = {
            ["Content-Type"] = "application/json"
          },
        })
        assert.res_status(201, res)

        local res = assert(client:send {
          method = "GET",
          path = "/rbac/roles/mock-role/entities",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same(2, #json.data)
        assert.same({ "read" }, json.data[1].actions)
      end)

      it("limits the size of returned entities", function()
        local res = assert(client:send {
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

        local res = assert(client:send {
          method = "GET",
          path = "/rbac/roles/mock-role/entities?size=1",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same(0, #json.data)
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
          path = "/consumers",
          body = {
            username = "c13579",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        local e_id = json.id

        res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/mock-role/entities",
          body = {
            entity_id = e_id,
            entity_type = "consumers",
            actions = "read",
          },
          headers = {
            ["Content-Type"] = "application/json"
          },
        })
        assert.res_status(201, res)

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
          method = "POST",
          path = "/consumers",
          body = {
            username = "c13579",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        local e_id = json.id

        local res = assert(client:send {
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

        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/mock-role/entities",
          body = {
            entity_id = e_id,
            entity_type = "consumers",
            actions = "read",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(201, res)

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

        assert.is_true(utils.is_valid_uuid(json.role.id))
        assert.is_true(utils.is_valid_uuid(json.entity_id))
        assert.same("foo", json.comment)
        assert.same({ "read" }, json.actions)
      end)

      it("update the relationship actions and displays them properly", function()
        local res = assert(client:send {
          method = "POST",
          path = "/consumers",
          body = {
            username = "c13579",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        local e_id = json.id

        local res = assert(client:send {
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

        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/mock-role/entities",
          body = {
            entity_id = e_id,
            entity_type = "consumers",
            actions = "read",
            comment = "foo",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(201, res)

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
            method = "POST",
            path = "/consumers",
            body = {
              username = "c13579",
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          local e_id = json.id

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
            method = "POST",
            path = "/consumers",
            body = {
              username = "c13579",
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          local e_id = json.id

          local res = assert(client:send {
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
          method = "POST",
          path = "/consumers",
          body = {
            username = "c13579",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        local e_id = json.id

        local res = assert(client:send {
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

        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/mock-role/entities",
          body = {
            entity_id = e_id,
            entity_type = "consumers",
            actions = "read",
            comment = "foo",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(201, res)

        local res = assert(client:send {
          method = "DELETE",
          path = "/rbac/roles/mock-role/entities/" .. e_id,
        })

        assert.res_status(204, res)

        local res = assert(client:send {
          method = "GET",
          path = "/rbac/roles/mock-role/entities/" .. e_id,
        })

        assert.res_status(404, res)
      end)

      describe("errors", function()
        it("when the given role does not exist", function()
          local res = assert(client:send {
            method = "POST",
            path = "/consumers",
            body = {
              username = "c13579",
            },
            headers = {
              ["Content-Type"] = "application/json",
            }
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          local e_id = json.id

          local res = assert(client:send {
            method = "DELETE",
            path = "/rbac/roles/dne-role/entities/" .. e_id,
          })

          assert.res_status(404, res)
        end)

        it("returns 204 even when not found", function()
          local res = assert(client:send {
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

          local res = assert(client:send {
            method = "DELETE",
            path = "/rbac/roles/mock-role/entities/" .. utils.uuid(),
          })

          assert.res_status(204, res)
        end)
        it("when the given entity is not a valid UUID", function()
          local res = assert(client:send {
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
        local res

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
        local res

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
        post("/workspaces", {name = "ws1234"})
        post("/ws1234/rbac/roles", {name = "ws1234-admin"})
        local perm = post("/ws1234/rbac/roles/ws1234-admin/endpoints",
          {actions = "*", endpoint="*"})
        assert.True(compare_no_order({ "delete", "create", "update", "read" }, perm.actions))
        assert.same("*", perm.endpoint)
        assert.is_false(perm.negative)
        assert.same("ws1234", perm.workspace)
      end)

      describe("errors", function()
        it("on duplicate PK", function()
          local res

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
          assert.res_status(201, res)

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

          assert.res_status(400, res)
        end)

        it("on invalid workspace", function()
          local res

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
        local res

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

        local res = assert(client:send {
          method = "GET",
          path = "/rbac/roles/mock-role/endpoints",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.data)
      end)

      it("limits the size of returned entities", function()
        local res

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

        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/mock-role/endpoints",
          body = {
            endpoint = "/foo",
            actions = "*",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, res)

        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/mock-role/endpoints",
          body = {
            endpoint = "/foo2",
            actions = "*",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, res)

        local res = assert(client:send {
          method = "GET",
          path = "/rbac/roles/mock-role/endpoints?size=1",
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.is_table(json.data)
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
        local res

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
        assert.res_status(201, res)

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
        local res

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
        assert.res_status(201, res)

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

      it("unescape workspace names properly for special chars", function()
        local ws_name = "ws-Áæ"
        local ws_name_escaped = escape_uri(ws_name)
        post("/workspaces", {name = ws_name})
        post("/".. ws_name_escaped .. "/rbac/roles", {name = "role1"})
        local res = assert(client:send {
          method = "POST",
          path = "/".. ws_name_escaped .. "/rbac/roles/role1/endpoints/",
          body = {
            endpoint = "/foo",
            actions = "*",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, res)

        local endpoint_path = "/".. ws_name_escaped .. "/rbac/roles/role1/endpoints/" .. ws_name_escaped .. "/foo"
        local res = assert(client:send {
          method = "GET",
          path = endpoint_path,
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equals(ws_name, json.workspace)
        assert.equals("/foo", json.endpoint)

        local res = assert(client:send {
          method = "PATCH",
          path = endpoint_path,
          body = {
            comment = "foo",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(200, res)

        local res = assert(client:send {
          method = "DELETE",
          path = endpoint_path,
        })
        assert.res_status(204, res)
        -- also check that the delete has not silently failed
        local res = assert(client:send {
          method = "GET",
          path = endpoint_path,
        })
        assert.res_status(404, res)
      end)

      it("does not retrieve entity if the wrong workspace is given", function()
        local res = assert(client:send {
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
        assert.res_status(201, res)

        local res = assert(client:send {
          method = "GET",
          path = "/rbac/roles/mock-role/endpoints/dne-workspace/foo",
        })

        assert.res_status(404, res)
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
          local res

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
        local res

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
        assert.res_status(201, res)

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

        assert.is_true(utils.is_valid_uuid(json.role.id))
        assert.same("foo", json.comment)
        table.sort(json.actions)
        assert.same({ "create", "delete", "read", "update" }, json.actions)
      end)

      it("updates * endpoint properly", function()
        local res

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
        assert.res_status(201, res)

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

        assert.is_true(utils.is_valid_uuid(json.role.id))
        assert.same("fooo", json.comment)
        table.sort(json.actions)
        assert.same({ "read" }, json.actions)
      end)

      it("updates / endpoint properly", function()
        local res

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
        assert.res_status(201, res)

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

        assert.is_true(utils.is_valid_uuid(json.role.id))
        assert.same("foooo", json.comment)
        table.sort(json.actions)
        assert.same({ "read" }, json.actions)
      end)

      it("update the relationship actions and displays them properly", function()
        local res

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

        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/mock-role/endpoints",
          body = {
            workspace = "mock-workspace",
            endpoint = "/foo",
            actions = "read",
            comment = "foo",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, res)

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
        local res

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

        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/mock-role/endpoints",
          body = {
            workspace = "mock-workspace",
            endpoint = "*",
            actions = "read",
            comment = "fooo",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, res)

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
        local res

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

        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/mock-role/endpoints",
          body = {
            workspace = "mock-workspace",
            endpoint = "/",
            actions = "read",
            comment = "foooo",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, res)

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

        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/mock-role/endpoints",
          body = {
            workspace = "mock-workspace",
            endpoint = "/foo",
            actions = "read",
            comment = "foo",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, res)

        local res = assert(client:send {
          method = "DELETE",
          path = "/rbac/roles/mock-role/endpoints/mock-workspace/foo",
        })

        assert.res_status(204, res)
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

        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/mock-role/endpoints",
          body = {
            workspace = "mock-workspace",
            endpoint = "*",
            actions = "read",
            comment = "foo",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, res)

        local res = assert(client:send {
          method = "DELETE",
          path = "/rbac/roles/mock-role/endpoints/mock-workspace/*",
        })

        assert.res_status(204, res)
      end)

      it("removes / endpoint association", function()
        local res = assert(client:send {
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

        local res = assert(client:send {
          method = "POST",
          path = "/rbac/roles/mock-role/endpoints",
          body = {
            workspace = "mock-workspace",
            endpoint = "/",
            actions = "read",
            comment = "foo",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, res)

        local res = assert(client:send {
          method = "DELETE",
          path = "/rbac/roles/mock-role/endpoints/mock-workspace/",
        })

        assert.res_status(204, res)
      end)
    end)
  end)

  describe("/rbac/roles/:name_or_id/endpoints/permissions", function()
    describe("GET", function()
      it("displays the role-endpoints permissions map for the given role", function()
        local res = assert(client:send {
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
end

for _, h in ipairs({ "", "Custom-Auth-Token" }) do
  describe("Admin API", function()
    local client
    local expected = h == "" and "Kong-Admin-Token" or h

    lazy_setup(function()
      assert(helpers.start_kong({
        rbac_auth_header = h ~= "" and h or nil,
      }))

      client = assert(helpers.admin_client())
    end)

    lazy_teardown(function()
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


for _, strategy in helpers.each_strategy() do
  describe("Admin API #".. strategy, function()
  local services

  lazy_setup(function()
    helpers.get_db_utils(strategy)

    assert(helpers.start_kong({
      database = strategy
    }))

    client = assert(helpers.admin_client())
    services = map(create_service, {1, 2, 3, 4})

    post("/rbac/users", {name = "bob", user_token = "bob "})
    -- user_token deliberately with a trailing space
    post("/rbac/users", {name = "trailingspace", user_token = "trailingspace "})
    -- user_token deliberately with a leading space
    post("/rbac/users", {name = "leadingspace", user_token = " leadingspace"})
    post("/rbac/roles" , {name = "mock-role"})
    post("/rbac/roles/mock-role/entities", {entity_id = services[2].id, entity_type = "services", actions = "read"})
    post("/rbac/roles/mock-role/entities", {entity_id = services[3].id, entity_type = "services", actions = "delete"})
    post("/rbac/roles/mock-role/entities", {entity_id = services[4].id, entity_type = "services", actions = "update"})
    post("/rbac/users/bob/roles", {roles = "mock-role"})
    post("/rbac/users/leadingspace/roles", {roles = "mock-role"})
    post("/rbac/users/trailingspace/roles", {roles = "mock-role"})

    helpers.stop_kong()
    assert(helpers.start_kong {
      database              = strategy,
      enforce_rbac          = "entity",
    })
  end)

  lazy_teardown(function()
    helpers.stop_kong()

    if client then
      client:close()
    end
  end)

  before_each(function()
    client = assert(helpers.admin_client())
  end)

  after_each(function()
    if client then
      client:close()
    end
  end)

  it(".select filters non accessible entities", function()
    local data = get("/services", {["Kong-Admin-User"] = "bob",
                               ["Kong-Admin-Token"] = "bob"}).data
    assert.equal(1, #data)
    assert.equal(services[2].id, data[1].id)
  end)

  it(".find_all returns 401 for invalid credentials", function()
    get("/services", {["Kong-Admin-Token"] = "wrong"}, 401)
    get("/services", nil, 401)
  end)

  it(".find errors for non permitted entities", function()
    get("/services/" .. services[1].id , {["Kong-Admin-Token"] = "wrong"}, 401)
    get("/services/" .. services[2].id , {["Kong-Admin-Token"] = "wrong"}, 401)
    get("/services/" .. services[1].id , {["Kong-Admin-Token"] = "bob"}, 403)
    get("/services/" .. services[2].id , {["Kong-Admin-Token"] = "bob"}, 200)
    -- check for positive authentication without a trailing space
    get("/services/" .. services[2].id , {["Kong-Admin-Token"] = "leadingspace"}, 200)
    get("/services/" .. services[2].id , {["Kong-Admin-Token"] = "trailingspace"}, 200)
  end)

  -- it(".update checks rbac via put", function()
  --   put("/services/" , {
  --     id = services[1].id,
  --     name = "new-name",
  --     created_at = "123",
  --     upstream_url = helpers.mock_upstream_url,
  --   }, {["Kong-Admin-Token"] = "bob"}, 403)

  --   put("/services/" , {
  --     id = services[4].id,
  --     name = "new-name",
  --     created_at = "123",
  --   }, {["Kong-Admin-Token"] = "bob"}, 200)
  -- end)

  it(".update checks rbac via patch", function()
    patch("/services/".. services[1].id, {name = "new-name"}, {["Kong-Admin-Token"] = "bob" }, 403)
    patch("/services/".. services[2].id, {name = "new-name"}, {["Kong-Admin-Token"] = "bob" }, 403)
    patch("/services/".. services[3].id, {name = "new-name"}, {["Kong-Admin-Token"] = "bob" }, 403)
    patch("/services/".. services[4].id, {name = "new-name"}, {["Kong-Admin-Token"] = "bob" }, 200)
  end)

  it(".delete checks rbac", function()
    delete("/services/" .. services[1].id, nil, 401)
    delete("/services/" .. services[2].id, nil, 401)
    delete("/services/" .. services[1].id, {["Kong-Admin-Token"] = "bob" }, 403)
    delete("/services/" .. services[2].id, {["Kong-Admin-Token"] = "bob" }, 403)
    delete("/services/" .. services[3].id, {["Kong-Admin-Token"] = "bob" }, 204)
  end)
end)

end

for _, strategy in helpers.each_strategy() do
  describe("RBAC users #" .. strategy, function()
  lazy_setup(function()
    helpers.get_db_utils(strategy)

    assert(helpers.start_kong({
      database = strategy,
    }))
    client = assert(helpers.admin_client())

    -- create 2 workspaces
    post("/workspaces", {name = "ws1"})
    post("/workspaces", {name = "ws2"})
    post("/workspaces", {name = "ws3"})

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

    -- user charlie (has read access to /kong endpoint)
    post("/ws1/rbac/users", {name = "charlie", user_token = "charlie"})
    post("/ws1/rbac/roles" , {name = "kong-role"})
    post("/ws1/rbac/roles/kong-role/endpoints", {endpoint = "/kong", actions = "read", workspace = "*"})
    post("/ws1/rbac/users/charlie/roles", {roles = "kong-role"})

    -- user diane (has permissions to /rbac endpoint so can create more roles ONLY for her workspace)
    post("/ws1/rbac/users", {name = "diane", user_token = "diane"})
    post("/ws1/rbac/roles" , {name = "ws1-limited"})
    post("/ws1/rbac/roles/ws1-limited/endpoints", {endpoint = "/rbac/roles", actions = "read,create,update,delete", workspace = "ws1"})
    post("/ws1/rbac/roles/ws1-limited/endpoints", {endpoint = "/rbac/roles/*/endpoints", actions = "read,create,update,delete", workspace = "ws1"})
    post("/ws1/rbac/users/diane/roles", {roles = "ws1-limited"})

    -- user god (all access)
    post("/ws1/rbac/users", {name = "god", user_token = "god"})
    post("/ws1/rbac/roles" , {name = "ws1-super-admin"})
    post("/ws1/rbac/roles/ws1-super-admin/endpoints", {endpoint = "*", actions = "read,create,update,delete", workspace = "*"})
    post("/ws1/rbac/roles/ws1-super-admin/entities", {entity_id = "*", actions = "*"})
    post("/ws1/rbac/users/god/roles", {roles = "ws1-super-admin"})


    helpers.stop_kong()
    assert(helpers.start_kong {
      database              = strategy,
      enforce_rbac          = "on",
    })
    client = assert(helpers.admin_client())
  end)

  lazy_teardown(function()
    helpers.stop_kong()

    if client then
      client:close()
    end
  end)

  it("cannot give permissions to workspaces they do not manage", function()
    post("/ws1/rbac/roles/ws1-admin/endpoints", {
      endpoint = "*",
      workspace = "ws2",
      actions = "read,create,update,delete"},
        {["Kong-Admin-Token"] = "bob"}, 403, "not allowed to create cross workspace permissions")
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

  it("user can add role in another workspace with ws1-super-admin role", function()
    post("/ws3/rbac/roles", {
      name = "new-ws3-role"
    },{["Kong-Admin-Token"] = "god"}, 201)
  end)

  it("user can't add a new role in another workspace with admin role", function()
    post("/ws3/rbac/roles", {
      name = "another-new-ws3-role"
    },{["Kong-Admin-Token"] = "bob"}, 403, "do not have permissions to create this resource")
  end)

  it("user can access wildcard workspace kong endpoint", function()
    get("/ws1/kong",{ ["Kong-Admin-Token"] = "charlie" }, 200)
    get("/ws2/kong",{ ["Kong-Admin-Token"] = "charlie" }, 200)
  end)

  -- 
  it("diane can only manage endpoints in ws1 workspace", function()
    post("/ws1/rbac/roles", { name = "diane-test1" },
      {["Kong-Admin-Token"] = "diane"}, 201)
    post("/ws1/rbac/roles/diane-test1/endpoints", { endpoint = "/1", actions = "*" },
      {["Kong-Admin-Token"] = "diane"}, 201)
    post("/ws1/rbac/roles/diane-test1/endpoints", { endpoint = "/2", actions = "*", workspace="ws1" },
      {["Kong-Admin-Token"] = "diane"}, 201)
    post("/ws1/rbac/roles/diane-test1/endpoints", { endpoint = "/3", actions = "*", workspace="ws2" },
      {["Kong-Admin-Token"] = "diane"}, 403, "not allowed to create cross workspace permissions")
    post("/ws1/rbac/roles/diane-test1/endpoints", { endpoint = "/4", actions = "*", workspace="*" },
      {["Kong-Admin-Token"] = "diane"}, 403, "not allowed to create cross workspace permissions")
      post("/ws2/rbac/roles", { name = "diane-test1" },
      {["Kong-Admin-Token"] = "diane"}, 403, "do not have permissions to create this resource")
  end)

end)
end
