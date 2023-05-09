-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local ee_helpers = require "spec-ee.helpers"

for _, strategy in helpers.each_strategy({"postgres"}) do
  describe("Keyring [#" .. strategy .. "]", function()
    local admin_client

    lazy_setup(function()
      local _, db = helpers.get_db_utils(strategy, {
        "keyring_meta",
        "keyring_keys",
        "rbac_users",
        "rbac_roles",
        "rbac_user_roles",
        "admins",
      })

      local _, _, err = ee_helpers.register_rbac_resources(db)
      assert.is_nil(err)

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        keyring_enabled = "on",
        keyring_strategy = "cluster",
        keyring_recovery_public_key = "spec-ee/fixtures/keyring/pub.pem",
        enforce_rbac = "on", -- with RBAC
      }))
    end)

    lazy_teardown(function()
      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong()
    end)

    before_each(function()
      admin_client = helpers.admin_client()
    end)

    describe("Admin API", function()
      it("/keyring/generate POST should succeed", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/keyring/generate",
          headers = {
            ["Kong-Admin-Token"] = "letmein-default",
          },
        })
        assert.res_status(201, res)
      end)
    end)
  end)
end
