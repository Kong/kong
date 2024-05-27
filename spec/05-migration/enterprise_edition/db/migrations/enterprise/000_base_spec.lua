-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local DB = require "kong.db"
local cycle_aware_deep_copy = require("kong.tools.table").cycle_aware_deep_copy

for _, strategy in helpers.each_strategy() do

  local function init_db()
    local conf = cycle_aware_deep_copy(helpers.test_conf)

    local db = assert(DB.new(conf, strategy))
    assert(db:init_connector())
    assert(db:connect())
    finally(function()
      db.connector:close()
    end)
    --assert(db.plugins:load_plugin_schemas(helpers.test_conf.loaded_plugins))
    return db
  end

  describe("bootstrapping [#" .. strategy .. "]", function()
    it("KONG_PASSWORD contains single quote", function()
      local db = init_db()
      local password = "123'45''678"

      helpers.setenv("KONG_PASSWORD", password)
      assert(db:schema_reset())

      helpers.bootstrap_database(db)

      local admin, err = db.rbac_users:select_by_name("kong_admin")
      assert.is_nil(err)
      assert.same(password, admin.user_token)

      -- recover
      helpers.unsetenv("KONG_PASSWORD")
      assert.equal(nil, os.getenv("KONG_PASSWORD"))
      assert(db:schema_reset())
    end)

  end)
end
