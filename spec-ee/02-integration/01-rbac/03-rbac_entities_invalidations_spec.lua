-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson        = require "cjson"
local helpers      = require "spec.helpers"
local ee_helpers   = require "spec-ee.helpers"
local kong_vitals = require "kong.vitals"


local POLL_INTERVAL = 0.3


local function wait_until_http_client_is(port, status, params)
  helpers.wait_until(function()
    local httpc = helpers.http_client("127.0.0.1", port)
    local res_2 = httpc:send(params)
    if not res_2 then
      httpc:close()
    end
    local res_status = res_2.status
    httpc:close()
    return res_status == status
  end)
end


local function wait_until_admin_client_1_is(status, params)
  return wait_until_http_client_is(8001, status, params)
end


local function wait_until_admin_client_2_is(status, params)
  return wait_until_http_client_is(9001, status, params)
end


for _, strategy in helpers.each_strategy() do
for _, role in ipairs({"traditional", "control_plane"}) do

describe("rbac entities are invalidated with db: #" .. strategy .. ", role: #" .. role, function()

  local admin_client_1

  local db, bp

  setup(function()
    bp, db = helpers.get_db_utils(strategy)

    assert(helpers.start_kong {
      log_level                    = "debug",
      prefix                       = "servroot1",
      database                     = strategy,
      proxy_listen                 = "0.0.0.0:8000, 0.0.0.0:8443 ssl",
      admin_listen                 = "0.0.0.0:8001",
      admin_gui_listen             = "0.0.0.0:8002",
      portal_gui_listen            = "0.0.0.0:8003",
      portal_api_listen            = "0.0.0.0:8004",
      cluster_listen               = "0.0.0.0:8005",
      cluster_telemetry_listen     = "0.0.0.0:8006",
      db_update_frequency          = POLL_INTERVAL,
      enforce_rbac                 = "on",
      role                         = role,
      cluster_cert                 = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key             = "spec/fixtures/kong_clustering.key",
      nginx_main_worker_processes  = 4,
    })

    assert(helpers.start_kong {
      log_level                    = "debug",
      prefix                       = "servroot2",
      database                     = strategy,
      proxy_listen                 = "0.0.0.0:9000, 0.0.0.0:9443 ssl",
      admin_listen                 = "0.0.0.0:9001",
      admin_gui_listen             = "0.0.0.0:9999",
      portal_gui_listen            = "0.0.0.0:9003",
      portal_api_listen            = "0.0.0.0:9004",
      cluster_listen               = "0.0.0.0:9005",
      cluster_telemetry_listen     = "0.0.0.0:9006",
      db_update_frequency          = POLL_INTERVAL,
      enforce_rbac                 = "on",
      role                         = role,
      cluster_cert                 = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key             = "spec/fixtures/kong_clustering.key",
      nginx_main_worker_processes  = 4,
    })

    admin_client_1 = helpers.http_client("127.0.0.1", 8001)
  end)

  teardown(function()
    helpers.stop_kong("servroot1", true)
    helpers.stop_kong("servroot2", true)
  end)

  before_each(function()
    admin_client_1 = helpers.http_client("127.0.0.1", 8001)
  end)

  after_each(function()
    admin_client_1:close()
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

      if _G.kong then
        _G.kong.cache = helpers.get_cache(db)
        _G.kong.vitals = kong_vitals.new({
          db = db,
          ttl_seconds = 3600,
          ttl_minutes = 24 * 60,
          ttl_days = 30,
        })
      else
        _G.kong = {
          cache = helpers.get_cache(db),
          vitals = kong_vitals.new({
            db = db,
            ttl_seconds = 3600,
            ttl_minutes = 24 * 60,
            ttl_days = 30,
          })
        }
      end

      service = bp.services:insert()

      ee_helpers.register_rbac_resources(db)

      -- a few extra mock entities for our test

      db.rbac_users:insert({
        name = "alice",
        user_token = "alice",
      })

      db.rbac_roles:insert({
        name = "foo",
      })

      -- this is bob
      db.rbac_users:insert({
        name = "bob",
        user_token = "bob",
      })

      local god = db.rbac_users:insert({
        name = "god",
        user_token = "god",
      })

      local superadmin = db.rbac_roles:select_by_name("superadmin")
      superadmin = superadmin or db.rbac_roles:select_by_name("super-admin")
      db.rbac_user_roles:insert({
        user = god,
        role = superadmin,
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

      wait_until_admin_client_2_is(200, {
        method  = "GET",
        path    = "/rbac/users/bob/roles",
        headers = {
          ["Kong-Admin-Token"] = "god",
          ["Content-Type"]     = "application/json",
        },
      })
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

      wait_until_admin_client_2_is(403, {
        method = "GET",
        path   = "/routes",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
      })

      -- give bob read-only access
      wait_until_admin_client_1_is(201, {
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

      wait_until_admin_client_1_is(200, {
        method = "GET",
        path   = "/routes",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
      })

      wait_until_admin_client_2_is(200, {
        method = "GET",
        path   = "/routes",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
      })
    end)

    it("on update", function()
      -- this is bob
      -- bob can see resources, but he cant create them!
      local res = admin_client_1:post("/routes", {
        body = {
          protocols = { "http" },
          hosts     = { "my.route.test" },
          service   = service,
        },
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"] = "application/json"}
      })
      assert.res_status(403, res)

      admin_client_1:post("/services/".. service.id .."/routes", {
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
        body = {
          name         = "example",
          hosts        = { "example.com" },
        },
      })
      admin_client_1:close()

      wait_until_admin_client_2_is(403, {
        method = "POST",
        path   = "/services/".. service.id .."/routes",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
        body = {
          name         = "example",
          hosts        = {"example.com"},
        },
      })

      -- give bob read-write access
      admin_client_1 = helpers.http_client("127.0.0.1", 8001)
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

      wait_until_admin_client_1_is(201, {
        method = "POST",
        path = "/services/".. service.id .."/routes",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
        body = {
          name         = "example",
          hosts        = {"example.com"},
        },
      })

      wait_until_admin_client_2_is(201, {
        method = "POST",
        path = "/services/".. service.id .."/routes",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
        body = {
          hosts = {"example.com"},
        },
      })
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

      wait_until_admin_client_1_is(403, {
        method = "POST",
        path   = "/services/".. service.id .."/routes",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
        body = {
          name         = "example",
          hosts        = {"example.com"},
        },
      })

      wait_until_admin_client_2_is(403, {
        method = "POST",
        path   = "/services/".. service.id .."/routes",
        headers = {
          ["Kong-Admin-Token"] = "bob",
          ["Content-Type"]     = "application/json",
        },
        body = {
          name         = "example2",
          hosts        = {"example.com"},
        },
      })
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
      wait_until_admin_client_1_is(401, {
        method  = "GET",
        path    = "/",
        headers = {
          ["Kong-Admin-Token"] = "herb",
        },
      })

      wait_until_admin_client_2_is(401, {
        method  = "GET",
        path    = "/",
        headers = {
          ["Kong-Admin-Token"] = "herb",
        },
      })
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
      wait_until_admin_client_1_is(200, {
        method  = "GET",
        path    = "/",
        headers = {
          ["Kong-Admin-Token"] = "herb",
        },
      })

      wait_until_admin_client_2_is(200, {
        method  = "GET",
        path    = "/",
        headers = {
          ["Kong-Admin-Token"] = "herb",
        },
      })
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

      wait_until_admin_client_2_is(403, {
        method  = "GET",
        path    = "/",
        headers = {
          ["Kong-Admin-Token"] = "alice",
        },
      })

      wait_until_admin_client_1_is(403, {
        method  = "GET",
        path    = "/status",
        headers = {
          ["Kong-Admin-Token"] = "alice",
        },
      })

      wait_until_admin_client_2_is(403, {
        method  = "GET",
        path    = "/status",
        headers = {
          ["Kong-Admin-Token"] = "alice",
        },
      })

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

      local admin_client_2 = helpers.http_client("127.0.0.1", 9001)
      finally(function()
        admin_client_2:close()
      end)

      local res_2 = assert(admin_client_2:send {
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

      wait_until_admin_client_1_is(200, {
        method = "GET",
        path   = "/",
        headers = {
          ["Kong-Admin-Token"] = "alice",
        },
      })

      wait_until_admin_client_2_is(200, {
        method = "GET",
        path   = "/",
        headers = {
          ["Kong-Admin-Token"] = "alice",
        },
      })
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

      wait_until_admin_client_1_is(200, {
        method = "GET",
        path   = "/status",
        headers = {
          ["Kong-Admin-Token"] = "alice",
        },
      })

      wait_until_admin_client_2_is(200, {
        method = "GET",
        path   = "/status",
        headers = {
          ["Kong-Admin-Token"] = "alice",
        },
      })
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

      wait_until_admin_client_1_is(403, {
        method = "GET",
        path   = "/",
        headers = {
          ["Kong-Admin-Token"] = "alice",
        },
      })

      wait_until_admin_client_2_is(403, {
        method = "GET",
        path   = "/",
        headers = {
          ["Kong-Admin-Token"] = "alice",
        },
      })
    end)
  end)
end)

end
end
