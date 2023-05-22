-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local operations = require "kong.db.migrations.operations.200_to_210"

return function(plugin_name)

  local function migration_up_f(ops, plugin_name)
    return function(connector)
      return ops:fixup_plugin_config(connector, plugin_name, function(config)
        if config.functions and #config.functions > 0 then
          config.access = config.functions
        end
        return true
      end)
    end
  end

  local function migration_teardown(ops, plugin_name)
    return function(connector)
      return ops:fixup_plugin_config(connector, plugin_name, function(config)
        if config.functions and #config.functions > 0 then
          config.functions = nil
        end
        return true
      end)
    end
  end

  return {
    postgres = {
      up = "",
      up_f = migration_up_f(operations.postgres.teardown, plugin_name),
      teardown = migration_teardown(operations.postgres.teardown, plugin_name),
    },
  }
end
