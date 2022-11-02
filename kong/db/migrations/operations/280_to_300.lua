-- Helper module for 280_to_300 migration operations.
--
-- Operations are versioned and specific to a migration so they remain
-- fixed in time and are not modified for use in future migrations.
--
-- If you want to reuse these operations in a future migration,
-- copy the functions over to a new versioned module.


local function render(template, keys)
  return (template:gsub("$%(([A-Z_]+)%)", keys))
end


--------------------------------------------------------------------------------
-- Postgres operations for Workspace migration
--------------------------------------------------------------------------------


local postgres = {

  up = {},

  teardown = {

    ------------------------------------------------------------------------------
    -- General function to fixup a plugin configuration
    fixup_plugin_config = function(_, connector, plugin_name, fixup_fn)
      local pgmoon_json = require("pgmoon.json")
      for plugin, err in connector:iterate("SELECT id, name, config FROM plugins") do
        if err then
          return nil, err
        end

        if plugin.name == plugin_name then
          local fix = fixup_fn(plugin.config)

          if fix then
            local sql = render(
              "UPDATE plugins SET config = $(NEW_CONFIG)::jsonb WHERE id = '$(ID)'", {
              NEW_CONFIG = pgmoon_json.encode_json(plugin.config),
              ID = plugin.id,
            })

            local _, err = connector:query(sql)
            if err then
              return nil, err
            end
          end
        end
      end

      return true
    end,
  },

}


--------------------------------------------------------------------------------
-- Cassandra operations for Workspace migration
--------------------------------------------------------------------------------


local cassandra = {

  up = {},

  teardown = {

    ------------------------------------------------------------------------------
    -- General function to fixup a plugin configuration
    fixup_plugin_config = function(_, connector, plugin_name, fixup_fn)
      local coordinator = assert(connector:get_stored_connection())
      local cassandra = require("cassandra")
      local cjson = require("cjson")

      for rows, err in coordinator:iterate("SELECT id, name, config FROM plugins") do
        if err then
          return nil, err
        end

        for i = 1, #rows do
          local plugin = rows[i]
          if plugin.name == plugin_name then
            if type(plugin.config) ~= "string" then
              return nil, "plugin config is not a string"
            end
            local config = cjson.decode(plugin.config)
            local fix = fixup_fn(config)

            if fix then
              local _, err = coordinator:execute("UPDATE plugins SET config = ? WHERE id = ?", {
                cassandra.text(cjson.encode(config)),
                cassandra.uuid(plugin.id)
              })
              if err then
                return nil, err
              end
            end
          end
        end
      end

      return true
    end,

  }

}


--------------------------------------------------------------------------------


return {
  postgres = postgres,
  cassandra = cassandra,
}
