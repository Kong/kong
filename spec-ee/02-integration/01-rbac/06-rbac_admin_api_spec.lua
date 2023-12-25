-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers    = require "spec.helpers"
local cjson      = require "cjson"
local ee_helpers   = require "spec-ee.helpers"
local kong_vitals = require "kong.vitals"

local admin_client

local function admin_request(method, path, body, excpected_status, token)
  local res = assert(admin_client:send {
    method = method,
    path = path,
    headers = {
      ["Content-Type"] = "application/json",
      ["Kong-Admin-Token"] = token,
    },
    body = body
  })
  local json = cjson.decode(assert.res_status(excpected_status or 200, res))
  return json
end

for _, strategy in helpers.each_strategy() do
  describe("Admin API - RBAC #" .. strategy, function()

    local db
    local ws1

    lazy_setup(function()
      _, db = helpers.get_db_utils(strategy, nil, nil, nil, false)
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

      assert(helpers.start_kong({
        database  = strategy,
        enforce_rbac = "on",
      }))

      ws1 = assert(db.workspaces:insert({
        name = "ws1",
      }))

      ee_helpers.register_rbac_resources(db)
      ee_helpers.register_rbac_resources(db, "ws1", ws1)
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      admin_client = assert(helpers.admin_client())
    end)

    after_each(function()
      if admin_client then admin_client:close() end
    end)

    describe("the admin with the role of super-admin", function()
      local ADMIN_TOKEN = "i-am-the-admin-token"

      lazy_setup(function()
        local admin = db.rbac_users:insert({
          name = "super-admin",
          user_token = ADMIN_TOKEN,
        })

        local superadmin = db.rbac_roles:select_by_name("superadmin") or db.rbac_roles:select_by_name("super-admin")
        db.rbac_user_roles:insert({
          user = admin,
          role = superadmin,
        })
      end)

      it("upsert is inserted and updated using PUT", function()
        local json = admin_request("PUT",
          "/services/upsert-route",
          { host = "upsert-host" }, 200, ADMIN_TOKEN)
        assert.same("upsert-host", json.host)

        json = admin_request("PUT",
          "/services/upsert-route",
          { host = "updated-host-after-upsert" }, 200, ADMIN_TOKEN)
        assert.same("updated-host-after-upsert", json.host)
      end)

      it("update is updated after adding using PUT", function()
        local json = admin_request("POST",
          "/services",
          {
            name = "added-route",
            host = "upsert-host"
          }, 201, ADMIN_TOKEN)
        assert.same("upsert-host", json.host)

        json = admin_request("PUT",
          "/services/added-route",
          {
            host = "updated-host-after-added"
          }, 200, ADMIN_TOKEN)
        assert.same("updated-host-after-added", json.host)
      end)
    end)

    describe("the admin with the role of admin when the workspace is default", function()

      lazy_setup(function()
        local admin = db.rbac_users:insert({
          name = "admin",
          user_token = "admin_handyshake",
        })

        local admin_role = db.rbac_roles:select_by_name("admin")
        db.rbac_user_roles:insert({
          user = admin,
          role = admin_role,
        })
      end)

      it("should not add an admin with the endpoint `/admins`", function()
        admin_request("POST",
          "/admins",
          {
            email = "john@konghq.com",
            username = "john",
          },
          403,
          "admin_handyshake"
        )
      end)
    end)

    describe("the admin with the role of admin when the workspace is non-default", function()
      local token = "workspace-admin_handyshake"
      lazy_setup(function()
        local admin = db.rbac_users:insert({
          name = "workspace-admin",
          user_token = token,
        })

        local admin_role = db.rbac_roles:select_by_name("admin", { workspace = ws1.id })
        db.rbac_user_roles:insert({
          user = admin,
          role = admin_role,
        })
      end)

      it("should not add an admin with the endpoint `/admins`", function()
        admin_request("POST",
          "/" .. ws1.name .. "/admins",
          {
            email = "john@konghq.com",
            username = "john",
          },
          403,
          token
        )
      end)
    end)
  end)
end
