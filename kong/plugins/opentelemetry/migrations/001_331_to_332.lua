local operations = require "kong.db.migrations.operations.331_to_332"


local function ws_migration_teardown(ops)
  return function(connector)
    return ops:fixup_plugin_config(connector, "opentelemetry", function(config)
      if not config.queue then
        return false
      end

      if config.queue.max_batch_size == 1 then
        config.queue.max_batch_size = 200
        return true
      end

      return false
    end)
  end
end


return {
  postgres = {
    up = "",
    teardown = ws_migration_teardown(operations.postgres.teardown),
  },
}
