local operations = require "kong.db.migrations.operations.200_to_210"


local function ws_migration_teardown(ops)
  return function(connector)
    return ops:fixup_plugin_config(connector, "http-log", function(config)
      local updated = false
      if type(config) == "table" then -- not required, but let's be defensive here
        local headers = config.headers
        if type(headers) == "table" then
          for header_name, value_array in pairs(headers) do
            if type(value_array) == "table" then
              -- only update if it's still a table, so it is reentrant
              headers[header_name] = value_array[1] or "empty header value"
              updated = true
            end
          end
        end
      end
      return updated
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
