-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local operations = require "kong.db.migrations.operations.280_to_300"

local function ws_migration_teardown(ops)
  return function(connector)
    ops:fixup_plugin_config(connector, "openid-connect", function(config)
      if config.session_redis_password == nil then
        config.session_redis_password = config.session_redis_auth
      end
      config.session_redis_auth = nil
      return true
    end)
  end
end


return {
  postgres = {
    up = "",
    teardown = ws_migration_teardown(operations.postgres.teardown),
  },
}
