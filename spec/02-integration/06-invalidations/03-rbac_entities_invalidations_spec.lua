local cjson        = require "cjson"
local helpers      = require "spec.helpers"
local dao_helpers  = require "spec.02-integration.03-dao.helpers"


local POLL_INTERVAL = 0.3


dao_helpers.for_each_dao(function(kong_conf)

describe("rbac entities are invalidated with db: " .. kong_conf.database, function()

  local admin_client_1
  local admin_client_2

  local dao
  local wait_for_propagation

  setup(function()
    local kong_dao_factory = require "kong.dao.factory"
    dao = assert(kong_dao_factory.new(kong_conf))
    dao:truncate_tables()
    helpers.run_migrations(dao)

    local db_update_propagation = kong_conf.database == "cassandra" and 3 or 0

    assert(helpers.start_kong {
      log_level             = "debug",
      prefix                = "servroot1",
      database              = kong_conf.database,
      proxy_listen          = "0.0.0.0:8000",
      proxy_listen_ssl      = "0.0.0.0:8443",
      admin_listen          = "0.0.0.0:8001",
      admin_gui_listen      = "0.0.0.0:8002",
      admin_ssl             = false,
      admin_gui_ssl         = false,
      db_update_frequency   = POLL_INTERVAL,
      db_update_propagation = db_update_propagation,
      rbac                  = "on",
    })

    assert(helpers.start_kong {
      log_level             = "debug",
      prefix                = "servroot2",
      database              = kong_conf.database,
      proxy_listen          = "0.0.0.0:9000",
      proxy_listen_ssl      = "0.0.0.0:9443",
      admin_listen          = "0.0.0.0:9001",
      admin_gui_listen      = "0.0.0.0:9002",
      admin_ssl             = false,
      admin_gui_ssl         = false,
      db_update_frequency   = POLL_INTERVAL,
      db_update_propagation = db_update_propagation,
      rbac                  = "on",
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

    dao:truncate_tables()
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
    setup(function()
      local utils = require "kong.tools.utils"
      local bit   = require "bit"
      local rbac  = require "kong.rbac"
      local bxor  = bit.bxor

      -- default permissions and roles
      -- load our default resources and create our initial permissions
      -- this is similar to what occurs in the real migrations
      rbac.load_resource_bitfields(dao)

      -- action int for all
      local action_bits_all = 0x0
      for k, v in pairs(rbac.actions_bitfields) do
        action_bits_all = bxor(action_bits_all, rbac.actions_bitfields[k])
      end

      -- resource int for all
      local resource_bits_all = 0x0
      for i = 1, #rbac.resource_bitfields do
        resource_bits_all = bxor(resource_bits_all, 2 ^ (i - 1))
      end

      local perms = {}
      local roles = {}

      -- read-only permission across all objects
      perms.read_only = dao.rbac_perms:insert({
        id = utils.uuid(),
        name = "read-only",
        resources = resource_bits_all,
        actions = rbac.actions_bitfields["read"],
        negative = false,
        comment = "Read-only permissions across all initial RBAC resources",
      })

      -- read,create,update,delete-resources for all objects
      perms.crud_all = dao.rbac_perms:insert({
        id = utils.uuid(),
        name = "full-access",
        resources = resource_bits_all,
        actions = action_bits_all,
        negative = false,
        comment = "Read/create/update/delete permissions across all objects",
      })

      -- negative rbac permissions (for the default 'admin' role)
      perms.no_rbac = dao.rbac_perms:insert({
        id = utils.uuid(),
        name = "no-rbac",
        resources = rbac.resource_bitfields["rbac"],
        actions = action_bits_all,
        negative = true,
        comment = "Explicit denial of all RBAC resources",
      })

      -- admin role with CRUD access to all resources except RBAC resource
      roles.admin = dao.rbac_roles:insert({
        id = utils.uuid(),
        name = "admin",
        comment = "CRUD access to most initial resources (no RBAC)",
      })
      -- the 'admin' role has 'full-access' + 'no-rbac' permissions
      dao.rbac_role_perms:insert({
        role_id = roles.admin.id,
        perm_id = perms.crud_all.id,
      })
      dao.rbac_role_perms:insert({
        role_id = roles.admin.id,
        perm_id = perms.no_rbac.id,
      })

      -- finally, a super user role who has access to all initial resources
      roles.super_admin = dao.rbac_roles:insert({
        id = utils.uuid(),
        name = "super-admin",
        comment = "Full CRUD access to all initial resources, including RBAC entities",
      })
      dao.rbac_role_perms:insert({
        role_id = roles.super_admin.id,
        perm_id = perms.crud_all.id,
      })

      -- now, create the roles and assign permissions to them

      -- first, a read-only role across everything
      roles.read_only = dao.rbac_roles:insert({
        id = utils.uuid(),
        name = "read-only",
        comment = "Read-only access across all initial RBAC resources",
      })
      -- this role only has the 'read-only' permissions
      dao.rbac_role_perms:insert({
        role_id = roles.read_only.id,
        perm_id = perms.read_only.id,
      })

      -- a few extra mock entities for our test
      dao.rbac_users:insert({
        name = "alice",
        user_token = "alice",
      })
      dao.rbac_roles:insert({
        name = "foo",
      })
      dao.rbac_perms:insert({
        name = "all-kong",
        actions = action_bits_all,
        resources = 0x2,
      })
      dao.rbac_perms:insert({
        name = "all-status",
        actions = action_bits_all,
        resources = 0x4,
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

      dao.rbac_user_roles:insert({
        user_id = god.id,
        role_id = roles.super_admin.id
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
        path   = "/apis",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
      })
      assert.res_status(401, res)

      res = assert(admin_client_2:send {
        method = "GET",
        path   = "/apis",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
      })
      assert.res_status(401, res)

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
        path   = "/apis",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
      })
      assert.res_status(200, res_1)

      wait_for_propagation()

      local res_2 = assert(admin_client_2:send {
        method = "GET",
        path   = "/apis",
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
      local res = assert(admin_client_1:send {
        method = "POST",
        path   = "/apis",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
        body = {
          name         = "example",
          hosts        = "example.com",
          upstream_url = "http://httpbin.org",
        },
      })
      assert.res_status(401, res)

      res = assert(admin_client_2:send {
        method = "POST",
        path   = "/apis",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
        body = {
          name         = "example",
          hosts        = "example.com",
          upstream_url = "http://httpbin.org",
        },
      })
      assert.res_status(401, res)

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

      local res_1 = assert(admin_client_1:send {
        method = "POST",
        path   = "/apis",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
        body = {
          name         = "example",
          hosts        = "example.com",
          upstream_url = "http://httpbin.org",
        },
      })
      assert.res_status(201, res_1)

      wait_for_propagation()

      local res_2 = assert(admin_client_2:send {
        method = "POST",
        path   = "/apis",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
        body = {
          name         = "example2",
          hosts        = "example.com",
          upstream_url = "http://httpbin.org",
        },
      })
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
        path   = "/apis",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
        body = {
          name         = "example",
          hosts        = "example.com",
          upstream_url = "http://httpbin.org",
        },
      })
      assert.res_status(401, res_1)

      wait_for_propagation()

      local res_2 = assert(admin_client_2:send {
        method = "POST",
        path   = "/apis",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
        body = {
          name         = "example2",
          hosts        = "example.com",
          upstream_url = "http://httpbin.org",
        },
      })
      assert.res_status(401, res_2)
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
          name = "herb",
          user_token = "herb",
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
      assert.res_status(401, res_1)

      local res_2 = assert(admin_client_2:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Kong-Admin-Token"] = "alice",
        },
      })
      assert.res_status(401, res_2)

      res_1 = assert(admin_client_1:send {
        method  = "GET",
        path    = "/status",
        headers = {
          ["Kong-Admin-Token"] = "alice",
        },
      })
      assert.res_status(401, res_1)

      res_2 = assert(admin_client_2:send {
        method  = "GET",
        path    = "/status",
        headers = {
          ["Kong-Admin-Token"] = "alice",
        },
      })
      assert.res_status(401, res_2)

      res_1 = assert(admin_client_1:send {
        method  = "GET",
        path    = "/rbac/users/alice/permissions",
        headers = {
          ["Kong-Admin-Token"] = "god",
        },
      })

      local body_1 = assert.res_status(200, res_1)
      local json_1 = cjson.decode(body_1)
      assert.same({}, json_1)

      res_2 = assert(admin_client_2:send {
        method  = "GET",
        path    = "/rbac/users/alice/permissions",
        headers = {
          ["Kong-Admin-Token"] = "god",
        },
      })

      local body_2 = assert.res_status(200, res_2)
      local json_2 = cjson.decode(body_2)
      assert.same({}, json_2)

      -- add the all-kong perm to the foo role
      local res = assert(admin_client_1:send {
        method  = "POST",
        path    = "/rbac/roles/foo/permissions",
        headers = {
          ["Kong-Admin-Token"] = "god",
          ["Content-Type"]     = "application/json",
        },
        body = {
          permissions = "all-kong",
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
        path    = "/rbac/roles/foo/permissions",
        headers = {
          ["Kong-Admin-Token"] = "god",
          ["Content-Type"]     = "application/json",
        },
        body = {
          permissions = "all-status",
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

    it("on delete", function()
      -- remove the all-kong permission to the foo role
      local res = assert(admin_client_1:send {
        method  = "DELETE",
        path    = "/rbac/roles/foo/permissions",
        headers = {
          ["Kong-Admin-Token"] = "god",
          ["Content-Type"]     = "application/json",
        },
        body = {
          permissions = "all-kong",
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
      assert.res_status(401, res_1)

      wait_for_propagation()

      local res_2 = assert(admin_client_2:send {
        method = "GET",
        path   = "/",
        headers = {
          ["Kong-Admin-Token"] = "alice",
        },
      })
      assert.res_status(401, res_2)
    end)
  end)
end)

end)
