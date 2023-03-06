-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local rbac    = require "kong.rbac"
local bit     = require "bit"
local bxor    = bit.bxor

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
end
