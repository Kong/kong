-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local operations = require "kong.db.migrations.operations.200_to_210"


local function ws_migration_teardown(ops)
  return function(connector)
    ops:fixup_plugin_config(connector, "canary", function(config)
      if config.hash == "whitelist" then
        config.hash = "allow"
      elseif config.hash == "blacklist" then
        config.hash = "deny"
      end
      return true
    end)
  end
end


return {
  postgres = {
    up = "",
    teardown = ws_migration_teardown(operations.postgres.teardown),
  },
  cassandra = {
    up = "",
    teardown = ws_migration_teardown(operations.cassandra.teardown),
  },
}
