-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers    = require "spec.helpers"
local rbac       = require "kong.rbac"
local bit        = require "bit"
local bxor       = bit.bxor
local ee_helpers = require "spec-ee.helpers"
local cjson      = require "cjson"

for _, strategy in helpers.each_strategy() do
  describe("delete role_entity_permission", function()
    local bp, db
    local admin_client
    local role_id, role_entity, route

    setup(function()
      local action_bits_all = 0x0
      for k, _ in pairs(rbac.actions_bitfields) do
        action_bits_all = bxor(action_bits_all, rbac.actions_bitfields[k])
      end
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "rbac_roles",
        "rbac_users",
        "rbac_role_entities",
      })

      local service = bp.services:insert {
        name = "example-service",
        host = "example.com"
      }

      route = bp.routes:insert {
        name = "example-route",
        paths = { "/test" },
        service = { id = service.id }
      }

      role_id = bp.rbac_roles:insert().id

      local user_id = bp.rbac_users:insert({
        name = "user0",
        user_token = "token0"
      }).id

      db.rbac_user_roles:insert {
        role = { id = role_id },
        user = { id = user_id }
      }

      role_entity = db.rbac_role_entities:insert {
        role = { id = role_id },
        entity_id = route.id,
        entity_type = "routes",
        actions = action_bits_all,
      }

      assert(helpers.start_kong {
        database                 = strategy,
        enforce_rbac             = "entity",
        admin_gui_auth           = "basic-auth",
        admin_gui_session_conf   = "{\"cookie_name\": \"kookie\", \"secret\": \"changeme\"}",
      })

      admin_client = helpers.admin_client()
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    it("when deleting route entity", function()
      local headers = { ["Kong-Admin-Token"] = "token0", }
      local res = admin_client:send {
        method  = "DELETE",
        path    = "/routes/example-route",
        headers = headers,
      }
      assert.res_status(204, res)

      res = admin_client:send {
        method  = "GET",
        path    = "/routes/example-route",
        headers = headers,
      }
      local body = assert.res_status(404, res)
      assert.equal("{\"message\":\"Not found\"}", body)

      role_entity = db.rbac_role_entities:select {
        role = { id = role_id },
        entity_id = route.id,
      }
      assert.is_nil(role_entity)
    end)
  end)

  describe("cascade delete", function()
    local ADMIN_TOKEN = "user-a-token"
    local admin_client
    local role_id

    local function admin_request(method, path, body, excpected_status)
      local res = assert(admin_client:send {
        method = method,
        path = path,
        headers = {
          ["Kong-Admin-Token"] = ADMIN_TOKEN,
          ["Content-Type"] = "application/json",
        },
        body = body
      })
      local body = assert.res_status(excpected_status or 200, res)
      if excpected_status == 204 then
        return nil
      end
      local json = cjson.decode(body)
      return json.data
    end

    setup(function()
      local _, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "rbac_roles",
        "rbac_users",
        "rbac_role_entities",
        "rbac_user_roles",
      })

      ee_helpers.register_rbac_resources(db)

      -- create user-a
      local usera = db.rbac_users:insert({
        name = "user-a",
        user_token = ADMIN_TOKEN,
      })
      local usera_default_role = db.rbac_roles:select_by_name(usera.name)
      role_id = usera_default_role.id

      -- grant super-admin role to user user-a
      local admin_role = db.rbac_roles:select_by_name("super-admin")
      db.rbac_user_roles:insert({
        user = usera,
        role = admin_role,
      })

      assert(helpers.start_kong {
        database                 = strategy,
        enforce_rbac             = "entity",
        admin_gui_auth           = "basic-auth",
        admin_gui_session_conf   = "{\"cookie_name\": \"kookie\", \"secret\": \"changeme\"}",
      })

      admin_client = helpers.admin_client()
    end)

    teardown(function()
      helpers.stop_kong(nil, true)
    end)

    it("rbac_role_entities should be removed after a consumer is deleted", function()
      admin_request("POST", "/consumers", { username = "foo" }, 201)
      admin_request("POST", "/consumers/foo/acls/", { group = "00000000-0000-0000-0000-000000000000" } , 201)

      local data = admin_request("GET", "/rbac/roles/" .. role_id  .. "/entities", nil, 200)
      local has_acls = false
      for _, e in ipairs(data) do
        if e.entity_type == "acls" then
          has_acls = true
        end
      end
      assert.is_true(has_acls)

      -- delete a consuemr
      admin_request("DELETE", "/consumers/foo", nil, 204)

      -- rbac_role_entities of acls should be removed
      local data = admin_request("GET", "/rbac/roles/" .. role_id  .. "/entities", nil, 200)

      for _, e in ipairs(data) do
        -- records with entity_type = acls should be completed deleted
        assert.is_not_equal("acls", e.entity_type)
      end
    end)
  end)
end
