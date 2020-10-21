-- remove repeated targets, the older ones are not useful anymore. targets with
-- weight 0 will be kept, as we cannot tell which were deleted and which were
-- explicitly set as 0.
local function c_remove_unused_targets(coordinator)
  local cassandra = require "cassandra"
  local upstream_targets = {}
  for row, err in coordinator:iterate("SELECT id, upstream_id, target, created_at FROM targets") do
    if err then
      return nil, err
    end

    local key = string.format("%s:%s", row.upstream_id, row.target)

    if not upstream_targets[key] then
      upstream_targets[key] = { n = 0 }
    end

    upstream_targets[key].n = upstream_targets[key].n + 1
    upstream_targets[key][upstream_targets[key].n] = { row.id, row.created_at }
  end

  local sort = function(a, b)
    return a[2] > b[2]
  end

  for _, targets in pairs(upstream_targets) do
    if targets.n > 1 then
      table.sort(targets, sort)

      for i = 2, targets.n do
        local _, err = coordinator.execute("DELETE FROM targets WHERE id = ?", {
          cassandra.uuid(targets[i][1])
        })

        if err then
          return nil, err
        end
      end
    end
  end

  return true
end


return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "clustering_data_planes" (
        id             UUID PRIMARY KEY,
        hostname       TEXT NOT NULL,
        ip             TEXT NOT NULL,
        last_seen      TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        config_hash    TEXT NOT NULL,
        ttl            TIMESTAMP WITH TIME ZONE
      );
      CREATE INDEX IF NOT EXISTS clustering_data_planes_ttl_idx ON clustering_data_planes (ttl);

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "routes" ADD "request_buffering" BOOLEAN;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "routes" ADD "response_buffering" BOOLEAN;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
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
        ]])

      if err then
        return nil, err
      end

      return true
    end
  },
  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS clustering_data_planes(
        id uuid,
        hostname text,
        ip text,
        last_seen timestamp,
        config_hash text,
        PRIMARY KEY (id)
      ) WITH default_time_to_live = 1209600;

      ALTER TABLE routes ADD request_buffering boolean;
      ALTER TABLE routes ADD response_buffering boolean;
    ]],
    teardown = function(connector)
      local coordinator = assert(connector:get_stored_connection())
      local _, err = c_remove_unused_targets(coordinator)
      if err then
        return nil, err
      end

      return true
    end
  }
}
