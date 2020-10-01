-- Helper module for 200_to_210 migration operations.
--
-- Operations are versioned and specific to a migration so they remain
-- fixed in time and are not modified for use in future migrations.
--
-- If you want to reuse these operations in a future migration,
-- copy the functions over to a new versioned module.


local ngx = ngx
local uuid = require "resty.jit-uuid"
local cassandra = require "cassandra"


local default_ws_id = uuid.generate_v4()


local function render(template, keys)
  return (template:gsub("$%(([A-Z_]+)%)", keys))
end


local function cassandra_get_default_ws(coordinator)
  local rows, err = coordinator:execute("SELECT id FROM workspaces WHERE name='default'")
  if err then
    return nil, err
  end

  if not rows
     or not rows[1]
     or not rows[1].id
  then
    return nil
  end

  return rows[1].id
end


local function cassandra_create_default_ws(coordinator)
  local created_at = ngx.time() * 1000

  local _, err = coordinator:execute("INSERT INTO workspaces(id, name, created_at) VALUES (?, 'default', ?)", {
    cassandra.uuid(default_ws_id),
    cassandra.timestamp(created_at)
  })
  if err then
    return nil, err
  end

  return cassandra_get_default_ws(coordinator) or default_ws_id
end


local function cassandra_ensure_default_ws(coordinator)

  local default_ws, err = cassandra_get_default_ws(coordinator)
  if err then
    return nil, err
  end

  if default_ws then
    return default_ws
  end

  return cassandra_create_default_ws(coordinator)
end


--------------------------------------------------------------------------------
-- Postgres operations for Workspace migration
--------------------------------------------------------------------------------


local postgres = {

  up = [[
  ]],

  teardown = {

    ------------------------------------------------------------------------------
    -- Update composite cache keys to workspace-aware formats
    ws_update_composite_cache_key = function(_, connector, table_name, is_partitioned)
      local _, err = connector:query(render([[
        UPDATE "$(TABLE)"
        SET cache_key = CONCAT(cache_key, ':',
                               (SELECT id FROM workspaces WHERE name = 'default'))
        WHERE cache_key LIKE '%:';
      ]], {
        TABLE = table_name,
      }))
      if err then
        return nil, err
      end

      return true
    end,
  },

}


--------------------------------------------------------------------------------
-- Cassandra operations for Workspace migration
--------------------------------------------------------------------------------


local cassandra = {

  up = [[
  ]],

  teardown = {

    ------------------------------------------------------------------------------
    -- Update composite cache keys to workspace-aware formats
    ws_update_composite_cache_key = function(_, connector, table_name, is_partitioned)
      local coordinator = assert(connector:connect_migrations())
      local default_ws, err = cassandra_ensure_default_ws(coordinator)
      if err then
        return nil, err
      end

      if not default_ws then
        return nil, "unable to find a default workspace"
      end

      for rows, err in coordinator:iterate("SELECT id, cache_key FROM " .. table_name) do
        if err then
          return nil, err
        end

        for i = 1, #rows do
          local row = rows[i]
          if row.cache_key:match(":$") then
            local cql = render([[
              UPDATE $(TABLE) SET cache_key = '$(CACHE_KEY)' WHERE $(PARTITION) id = $(ID)
            ]], {
              TABLE = table_name,
              CACHE_KEY = row.cache_key .. ":" .. default_ws,
              PARTITION = is_partitioned
                        and "partition = '" .. table_name .. "' AND"
                        or  "",
              ID = row.id,
            })

            local _, err = coordinator:execute(cql)
            if err then
              return nil, err
            end
          end
        end
      end

      return true
    end,

  }

}


--------------------------------------------------------------------------------
-- Higher-level operations for Workspace migration
--------------------------------------------------------------------------------

local function ws_adjust_data(ops, connector, entities)
  for _, entity in ipairs(entities) do

    if entity.cache_key and #entity.cache_key > 1 then
      local _, err = ops:ws_update_composite_cache_key(connector, entity.name, entity.partitioned)
      if err then
        return nil, err
      end
    end
  end

  return true
end

postgres.teardown.ws_adjust_data = ws_adjust_data
cassandra.teardown.ws_adjust_data = ws_adjust_data


--------------------------------------------------------------------------------


return {
  postgres = postgres,
  cassandra = cassandra,
}
