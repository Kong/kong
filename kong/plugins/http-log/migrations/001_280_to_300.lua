local operations = require "kong.db.migrations.operations.280_to_300"


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
              if not next(value_array) then
                -- In <=2.8, while it is possible to set a header with an empty
                -- array of values, the gateway won't send the header with no
                -- value to the defined HTTP endpoint. To match this behavior,
                -- we'll remove the header.
                headers[header_name] = nil
              else
                -- When multiple header values were provided, the gateway would
                -- send all values, deliminated by a comma & space characters.
                headers[header_name] = table.concat(value_array, ", ")
              end
              updated = true
            end
          end

          -- When there are no headers set after the modifications, set to null
          -- in order to avoid setting to an empty object.
          if updated and not next(headers) then
            local cjson = require "cjson"
            config.headers = cjson.null
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
