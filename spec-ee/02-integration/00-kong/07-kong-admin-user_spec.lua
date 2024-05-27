-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local crypto = require "kong.plugins.basic-auth.crypto"
local cycle_aware_deep_copy = require("kong.tools.table").cycle_aware_deep_copy
local DB = require "kong.db"

for _, strategy in helpers.each_strategy() do

  after_each(function()
      helpers.unsetenv("KONG_PASSWORD")
      assert.equal(nil, os.getenv("KONG_PASSWORD"))
  end)

  local function init_db()
    local conf = cycle_aware_deep_copy(helpers.test_conf)

    local db = assert(DB.new(conf, strategy))
    assert(db:init_connector())
    assert(db:connect())
    finally(function()
      db.connector:close()
    end)
    assert(db.plugins:load_plugin_schemas(helpers.test_conf.loaded_plugins))
    return db
  end

  describe("bootstrapping [#" .. strategy .. "]", function()
    it("creates an admin with correct basicauth ", function()
      local db = init_db()

      helpers.setenv("KONG_PASSWORD", "foo")
      assert(db:schema_reset())

      helpers.bootstrap_database(db)

      local n = 0
      for _ in db.admins:each() do
        n = n + 1
      end
      assert.equal(1, n)

      local default_ws = assert(db.workspaces:select_by_name("default"))

      local consumer = db.consumers:each()()
      local cred = db.basicauth_credentials:each(nil, { nulls = true, show_ws_id = true })()
      assert(cred.ws_id == default_ws.id)
      assert.same(crypto.hash(consumer.id, os.getenv("KONG_PASSWORD")), cred.password)
    end)

  end)
end
