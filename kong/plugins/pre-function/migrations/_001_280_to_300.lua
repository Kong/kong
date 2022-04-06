local operations = require "kong.db.migrations.operations.200_to_210"

return function(plugin_name)

  local function migration_teardown(ops, plugin_name)
    return function(connector)
      return ops:fixup_plugin_config(connector, plugin_name, function(config)
        if config.functions and #config.functions > 0 then
          config.access = config.functions
          config.functions = nil
        end
        return true
      end)
    end
  end

  return {
    postgres = {
      up = "",
      teardown = migration_teardown(operations.postgres.teardown, plugin_name),
    },
  
    cassandra = {
      up = "",
      teardown = migration_teardown(operations.cassandra.teardown, plugin_name),
    },
  }
end
