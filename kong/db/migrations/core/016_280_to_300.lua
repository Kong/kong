-- remove repeated targets, the older ones are not useful anymore. targets with
-- weight 0 will be kept, as we cannot tell which were deleted and which were
-- explicitly set as 0.
local function c_remove_unused_targets(coordinator)
  local cassandra = require "cassandra"
  local upstream_targets = {}
  for rows, err in coordinator:iterate("SELECT id, upstream_id, target, created_at FROM targets") do
    if err then
      return nil, err
    end

    for _, row in ipairs(rows) do
      local key = string.format("%s:%s", row.upstream_id, row.target)

      if not upstream_targets[key] then
        upstream_targets[key] = {
          id = row.id,
          created_at = row.created_at,
        }
      else
        local to_remove
        if row.created_at > upstream_targets[key].created_at then
          to_remove = upstream_targets[key].id
          upstream_targets[key] = {
            id = row.id,
            created_at = row.created_at,
          }
        else
          to_remove = row.id
        end
        local _, err = coordinator:execute("DELETE FROM targets WHERE id = ?", {
          cassandra.uuid(to_remove)
        })

        if err then
          return nil, err
        end
      end
    end
  end

  return true
end


-- update cache_key for targets
local function c_update_target_cache_key(coordinator)
  local cassandra = require "cassandra"
  for rows, err in coordinator:iterate("SELECT id, upstream_id, target, ws_id FROM targets") do
    if err then
      return nil, err
    end

    for _, row in ipairs(rows) do
      local cache_key = string.format("targets:%s:%s::::%s", row.upstream_id, row.target, row.ws_id)

      local _, err = coordinator:execute("UPDATE targets SET cache_key = ? WHERE id = ? IF EXISTS", {
        cache_key, cassandra.uuid(row.id)
      })

      if err then
        return nil, err
      end
    end
  end

  return true
end


return {
  postgres = {
    up = [[
      DO $$
        BEGIN
          ALTER TABLE IF EXISTS ONLY "targets" ADD COLUMN "cache_key" TEXT UNIQUE;
        EXCEPTION WHEN duplicate_column THEN
          -- Do nothing, accept existing state
        END;
      $$;
    ]],
    teardown = function(connector)
      local _, err = connector:query([[
        DELETE FROM targets t1
              USING targets t2
              WHERE t1.created_at < t2.created_at
                AND t1.upstream_id = t2.upstream_id
                AND t1.target = t2.target;
        UPDATE targets SET cache_key = CONCAT('targets:', upstream_id, ':', target, '::::', ws_id);
        ]])

      if err then
        return nil, err
      end

      return true
    end
  },

  cassandra = {
    up = [[
      ALTER TABLE targets ADD cache_key text;
      CREATE INDEX IF NOT EXISTS targets_cache_key_idx ON targets(cache_key);
    ]],
    teardown = function(connector)
      local coordinator = assert(connector:get_stored_connection())
      local _, err = c_remove_unused_targets(coordinator)
      if err then
        return nil, err
      end

      _, err = c_update_target_cache_key(coordinator)
      if err then
        return nil, err
      end

      return true
    end
  },
}
