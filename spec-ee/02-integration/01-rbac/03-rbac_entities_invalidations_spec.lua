local cjson        = require "cjson"
local helpers      = require "spec.helpers"
local dao_helpers  = require "spec.02-integration.03-dao.helpers"
local rbac_migrations_defaults = require "kong.rbac.migrations.01_defaults"

local POLL_INTERVAL = 0.3


dao_helpers.for_each_dao(function(kong_conf)

describe("rbac entities are invalidated with db: " .. kong_conf.database, function()

  local admin_client_1
  local admin_client_2

  local dao, _, bp
  local wait_for_propagation

  setup(function()
    bp, _, dao = helpers.get_db_utils(kong_conf.database)
    local db_update_propagation = kong_conf.database == "cassandra" and 3 or 0

    assert(helpers.start_kong {
      log_level             = "debug",
      prefix                = "servroot1",
      database              = kong_conf.database,
      proxy_listen          = "0.0.0.0:8000, 0.0.0.0:8443 ssl",
      admin_listen          = "0.0.0.0:8001",
      admin_gui_listen      = "0.0.0.0:8002",
      portal_gui_listen     = "0.0.0.0:8003",
      portal_api_listen     = "0.0.0.0:8004",
      db_update_frequency   = POLL_INTERVAL,
      db_update_propagation = db_update_propagation,
      enforce_rbac          = "on",
    })

    assert(helpers.start_kong {
      log_level             = "debug",
      prefix                = "servroot2",
      database              = kong_conf.database,
      proxy_listen          = "0.0.0.0:9000, 0.0.0.0:9443 ssl",
      admin_listen          = "0.0.0.0:9001",
      admin_gui_listen      = "0.0.0.0:9002",
      portal_gui_listen     = "0.0.0.0:9003",
      portal_api_listen     = "0.0.0.0:9004",
      db_update_frequency   = POLL_INTERVAL,
      db_update_propagation = db_update_propagation,
      enforce_rbac          = "on",
    })

    admin_client_1 = helpers.http_client("127.0.0.1", 8001)
    admin_client_2 = helpers.http_client("127.0.0.1", 9001)

    wait_for_propagation = function()
      ngx.sleep(POLL_INTERVAL + db_update_propagation)
    end
  end)

  teardown(function()
    helpers.stop_kong("servroot1")
    helpers.stop_kong("servroot2")
  end)

  before_each(function()
    admin_client_1 = helpers.http_client("127.0.0.1", 8001)
    admin_client_2 = helpers.http_client("127.0.0.1", 9001)
  end)

  after_each(function()
    admin_client_1:close()
    admin_client_2:close()
  end)

  describe("RBAC (user_roles)", function()
    local service
    setup(function()
      local bit   = require "bit"
      local rbac  = require "kong.rbac"
      local bxor  = bit.bxor

      -- default permissions and roles
      -- load our default resources and create our initial permissions
      -- this is similar to what occurs in the real migrations
      -- rbac.load_resource_bitfields(dao)

      -- action int for all
      local action_bits_all = 0x0
      for k, v in pairs(rbac.actions_bitfields) do
        action_bits_all = bxor(action_bits_all, rbac.actions_bitfields[k])
      end

      service = bp.services:insert()

      rbac_migrations_defaults.up(nil, nil, dao)
      -- a few extra mock entities for our test

      dao.rbac_users:insert({
        name = "alice",
        user_token = "alice",
      })

      dao.rbac_roles:insert({
        name = "foo",
      })

      -- this is bob
      dao.rbac_users:insert({
        name = "bob",
        user_token = "bob",
      })

      local god = dao.rbac_users:insert({
        name = "god",
        user_token = "god",
      })

      local superadmin = dao.rbac_roles:find_all({name = "super-admin"})[1]
      dao.rbac_user_roles:insert({
        user_id = god.id,
        role_id = superadmin.id
      })

      -- populate cache with a miss on both nodes
      local res_1 = assert(admin_client_1:send {
        method  = "GET",
        path    = "/rbac/users/bob/roles",
        headers = {
          ["Kong-Admin-Token"] = "god",
          ["Content-Type"]     = "application/json",
        },
      })
      assert.res_status(200, res_1)

      local res_2 = assert(admin_client_2:send {
        method  = "GET",
        path    = "/rbac/users/bob/roles",
        headers = {
          ["Kong-Admin-Token"] = "god",
          ["Content-Type"]     = "application/json",
        },
      })
      assert.res_status(200, res_2)
    end)

    it("on create", function()
      -- this is bob
      -- bob cant see any resources!
      local res = assert(admin_client_1:send {
        method = "GET",
        path   = "/routes",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
      })
      assert.res_status(403, res)

      res = assert(admin_client_2:send {
        method = "GET",
        path   = "/routes",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
      })
      assert.res_status(403, res)

      -- give bob read-only access
      local admin_res = assert(admin_client_1:send {
        method = "POST",
        path   = "/rbac/users/bob/roles",
        body   = {
          roles = "read-only",
        },
        headers = {
          ["Kong-Admin-Token"] = "god",
          ["Content-Type"]     = "application/json",
        },
      })
      assert.res_status(201, admin_res)

      -- no need to wait for workers propagation (lua-resty-worker-events)
      -- because our test instance only has 1 worker

      local res_1 = assert(admin_client_1:send {
        method = "GET",
        path   = "/routes",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
      })
      assert.res_status(200, res_1)

      wait_for_propagation()

      local res_2 = assert(admin_client_2:send {
        method = "GET",
        path   = "/routes",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
      })
      assert.res_status(200, res_2)
    end)

    it("on update", function()
      -- this is bob
      -- bob can see resources, but he cant create them!
      local res = admin_client_1:post("/routes", {
        body = {
          protocols = { "http" },
          hosts     = { "my.route.com" },
          service   = service,
        },
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"] = "application/json"}
      })
      assert.res_status(403, res)

      local res = admin_client_1:post("/services/".. service.id .."/routes", {
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
        body = {
          name         = "example",
          hosts        = { "example.com" },
          upstream_url = helpers.mock_upstream_url,
        },
      })

      assert.res_status(403, res)

      res = assert(admin_client_2:send {
        method = "POST",
        path   = "/services/".. service.id .."/routes",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
        body = {
          name         = "example",
          hosts        = {"example.com"},
          upstream_url = helpers.mock_upstream_url,
        },
      })
      assert.res_status(403, res)

      -- give bob read-write access
      local admin_res = assert(admin_client_1:send {
        method = "POST",
        path   = "/rbac/users/bob/roles",
        body   = {
          roles = "admin",
        },
        headers = {
          ["Kong-Admin-Token"] = "god",
          ["Content-Type"]     = "application/json",
        },
      })
      assert.res_status(201, admin_res)

      -- no need to wait for workers propagation (lua-resty-worker-events)
      -- because our test instance only has 1 worker

      local res_1 = assert(admin_client_1:post("/services/".. service.id .."/routes", {
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
        body = {
          -- TODO:  add name after 1.0 merge
          -- name         = "example",
          hosts        = {"example.com"},
        },
      }))
      assert.res_status(201, res_1)

      wait_for_propagation()

      local res_2 = assert(admin_client_2:post("/services/".. service.id .."/routes", {
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
        body = {
          -- TODO:  add name after 1.0 merge
          -- name         = "example2",
          hosts        ={"example.com"},
        },
      }))
      assert.res_status(201, res_2)
    end)

    it("on delete", function()
      -- remove bob's write access
      local admin_res = assert(admin_client_1:send {
        method = "DELETE",
        path   = "/rbac/users/bob/roles",
        body   = {
          roles = "admin",
        },
        headers = {
          ["Kong-Admin-Token"] = "god",
          ["Content-Type"]     = "application/json",
        },
      })
      assert.res_status(204, admin_res)

      -- no need to wait for workers propagation (lua-resty-worker-events)
      -- because our test instance only has 1 worker

      local res_1 = assert(admin_client_1:send {
        method = "POST",
        path   = "/services/".. service.id .."/routes",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
        body = {
          name         = "example",
          hosts        = {"example.com"},
          upstream_url = helpers.mock_upstream_url,
        },
      })
      assert.res_status(403, res_1)

      wait_for_propagation()

      local res_2 = assert(admin_client_2:send {
        method = "POST",
        path   = "/services/".. service.id .."/routes",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
        body = {
          name         = "example2",
          hosts        = {"example.com"},
          upstream_url = helpers.mock_upstream_url,
        },
      })
      assert.res_status(403, res_2)
    end)
  end)

  describe("RBAC (enabled users)", function()
    it("on create", function()
      -- some initial prep
      local res = assert(admin_client_1:send {
        method  = "POST",
        path    = "/rbac/users",
        headers = {
          ["Kong-Admin-Token"] = "god",
          ["Content-Type"]     = "application/json",
        },
        body = {
          name = "herb",
          user_token = "herb",
          enabled = false,
        },
      })
      assert.res_status(201, res)

      res = assert(admin_client_1:send {
        method  = "POST",
        path    = "/rbac/users/herb/roles",
        headers = {
          ["Kong-Admin-Token"] = "god",
          ["Content-Type"]     = "application/json",
        },
        body = {
          roles = "read-only",
        },
      })
      assert.res_status(201, res)

      -- herb cannot hit /
      local res_1 = assert(admin_client_1:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Kong-Admin-Token"] = "herb",
        },
      })
      assert.res_status(401, res_1)

      wait_for_propagation()

      local res_2 = assert(admin_client_2:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Kong-Admin-Token"] = "herb",
        },
      })
      assert.res_status(401, res_2)
    end)

    it("on update", function()
      local res = assert(admin_client_1:send {
        method  = "PATCH",
        path    = "/rbac/users/herb",
        headers = {
          ["Kong-Admin-Token"] = "god",
          ["Content-Type"]     = "application/json",
        },
        body = {
          enabled = true,
        },
      })
      assert.res_status(200, res)

      -- herb can now hit /
      -- no need to wait for workers propagation (lua-resty-worker-events)
      -- because our test instance only has 1 worker
      local res_1 = assert(admin_client_1:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Kong-Admin-Token"] = "herb",
        },
      })
      assert.res_status(200, res_1)

      wait_for_propagation()

      local res_2 = assert(admin_client_2:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Kong-Admin-Token"] = "herb",
        },
      })
      assert.res_status(200, res_2)
    end)
  end)

  describe("RBAC (role_perms)", function()
    it("on create", function()
      -- some initial prep
      local res = assert(admin_client_1:send {
        method  = "POST",
        path    = "/rbac/users/alice/roles",
        headers = {
          ["Kong-Admin-Token"] = "god",
          ["Content-Type"]     = "application/json",
        },
        body = {
          roles = "foo",
        },
      })
      assert.res_status(201, res)

      -- cache prime
      -- alice cannot hit / or /status
      local res_1 = assert(admin_client_1:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Kong-Admin-Token"] = "alice",
        },
      })
      assert.res_status(403, res_1)

      local res_2 = assert(admin_client_2:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Kong-Admin-Token"] = "alice",
        },
      })
      assert.res_status(403, res_2)

      res_1 = assert(admin_client_1:send {
        method  = "GET",
        path    = "/status",
        headers = {
          ["Kong-Admin-Token"] = "alice",
        },
      })
      assert.res_status(403, res_1)

      res_2 = assert(admin_client_2:send {
        method  = "GET",
        path    = "/status",
        headers = {
          ["Kong-Admin-Token"] = "alice",
        },
      })
      assert.res_status(403, res_2)

      res_1 = assert(admin_client_1:send {
        method  = "GET",
        path    = "/rbac/users/alice/permissions",
        headers = {
          ["Kong-Admin-Token"] = "god",
        },
      })

      local body_1 = assert.res_status(200, res_1)
      local json_1 = cjson.decode(body_1)
      assert.same({endpoints = {}, entities = {}}, json_1)

      res_2 = assert(admin_client_2:send {
        method  = "GET",
        path    = "/rbac/users/alice/permissions",
        headers = {
          ["Kong-Admin-Token"] = "god",
        },
      })

      local body_2 = assert.res_status(200, res_2)
      local json_2 = cjson.decode(body_2)
      assert.same({endpoints = {}, entities = {}}, json_2)

      -- add the all-kong perm to the foo role
      local res = assert(admin_client_1:send {
        method  = "POST",
        path    = "/rbac/roles/foo/endpoints",
        headers = {
          ["Kong-Admin-Token"] = "god",
          ["Content-Type"]     = "application/json",
        },
        body = {
          endpoint = "*",
          actions = "read",
        },
      })
      assert.res_status(201, res)

      -- no need to wait for workers propagation (lua-resty-worker-events)
      -- because our test instance only has 1 worker

      local res_1 = assert(admin_client_1:send {
        method = "GET",
        path   = "/",
        headers = {
          ["Kong-Admin-Token"] = "alice",
        },
      })
      assert.res_status(200, res_1)

      wait_for_propagation()

      local res_2 = assert(admin_client_2:send {
        method = "GET",
        path   = "/",
        headers = {
          ["Kong-Admin-Token"] = "alice",
        },
      })
      assert.res_status(200, res_2)
    end)

    it("on update", function()
      -- add the all-status permission to the foo role
      local res = assert(admin_client_1:send {
        method  = "POST",
        path    = "/rbac/roles/foo/endpoints",
        headers = {
          ["Kong-Admin-Token"] = "god",
          ["Content-Type"]     = "application/json",
        },
        body = {
          endpoint = "/status",
          actions = "read",
        },
      })
      assert.res_status(201, res)

      -- no need to wait for workers propagation (lua-resty-worker-events)
      -- because our test instance only has 1 worker

      local res_1 = assert(admin_client_1:send {
        method = "GET",
        path   = "/status",
        headers = {
          ["Kong-Admin-Token"] = "alice",
        },
      })
      assert.res_status(200, res_1)

      wait_for_propagation()

      local res_2 = assert(admin_client_2:send {
        method = "GET",
        path   = "/status",
        headers = {
          ["Kong-Admin-Token"] = "alice",
        },
      })
      assert.res_status(200, res_2)
    end)

    pending("on delete", function()
      -- remove the all-kong permission to the foo role
      local res = assert(admin_client_1:send {
        method  = "DELETE",
        path    = "/rbac/roles/foo/endpoints",
        headers = {
          ["Kong-Admin-Token"] = "god",
          ["Content-Type"]     = "application/json",
        },
        body = {
          endpoint = "*",
          actions = "read",
        },
      })
      assert.res_status(204, res)

      -- no need to wait for workers propagation (lua-resty-worker-events)
      -- because our test instance only has 1 worker

      local res_1 = assert(admin_client_1:send {
        method = "GET",
        path   = "/",
        headers = {
          ["Kong-Admin-Token"] = "alice",
        },
      })
      assert.res_status(403, res_1)

      wait_for_propagation()

      local res_2 = assert(admin_client_2:send {
        method = "GET",
        path   = "/",
        headers = {
          ["Kong-Admin-Token"] = "alice",
        },
      })
      assert.res_status(403, res_2)
    end)
  end)
end)

end)
