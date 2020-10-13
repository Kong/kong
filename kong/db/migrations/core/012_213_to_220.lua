local fmt = string.format


local function pg_clean_repeated_targets(connector, upstream_id)
  local targets_query = fmt("SELECT id, created_at, target FROM targets WHERE upstream_id = '%s'", upstream_id)
  for target, err in connector:iterate(targets_query) do
    if err then
      return nil, err
    end
    local rep_tgt_query = fmt("SELECT id, created_at, target FROM targets WHERE upstream_id = '%s' AND target = '%s' AND id <> '%s'",
                              upstream_id, target.target, target.id)
    for rep_tgt, err in connector:iterate(rep_tgt_query) do
      if err then
        return nil, err
      end
      local tgt_to_clean
      if target.created_at >= rep_tgt.created_at then
        tgt_to_clean = rep_tgt
      else
        tgt_to_clean = target
      end

      local del_tgt_query = fmt("DELETE FROM targets WHERE id = '%s';", tgt_to_clean.id)
      local _, err = connector:query(del_tgt_query)
      if err then
        return nil, err
      end
    end
  end

  return true
end


-- remove repeated targets, the older ones are not useful anymore. targets with
-- weight 0 will be kept, as we cannot tell which were deleted and which were
-- explicitly set as 0.
local function pg_remove_unused_targets(connector)
  for upstream, err in connector:iterate("SELECT id FROM upstreams") do
    if err then
      return nil, err
    end

    local upstream_id = upstream and upstream.id
    if not upstream_id then
      return nil, err
    end

    local _, err = pg_clean_repeated_targets(connector, upstream_id)
    if err then
      return nil, err
    end

  end

  return true
end


local function c_clean_repeated_targets(coordinator, upstream_id)
  local cassandra = require 'cassandra'
  local rows, err = coordinator:execute(
    "SELECT id, created_at, target FROM targets WHERE upstream_id = ?",
    { cassandra.uuid(upstream_id), }
  )
  if err then
    return nil, err
  end

  for i = 1, #rows do
    local target = rows[i]
    local rep_tgt_rows, err = coordinator:execute(
      "SELECT id, created_at, target FROM targets "..
      "WHERE upstream_id = ? AND target = ? ALLOW FILTERING",
      {
        cassandra.uuid(upstream_id),
        cassandra.text(target.target),
      }
    )
    if err then
      return nil, err
    end

    for j = i, #rep_tgt_rows do
      local rep_tgt = rep_tgt_rows[j]
      if rep_tgt.id ~= target.id then
        local tgt_to_clean
        if target.created_at >= rep_tgt.created_at then
          tgt_to_clean = rep_tgt
        else
          tgt_to_clean = target
        end

        local _, err = coordinator:execute(
          "DELETE FROM targets WHERE id = ?",
          { cassandra.uuid(tgt_to_clean.id) }
        )
        if err then
          return nil, err
        end
      end
    end
  end

  return true
end


-- remove repeated targets, the older ones are not useful anymore. targets with
-- weight 0 will be kept, as we cannot tell which were deleted and which were
-- explicitly set as 0.
local function c_remove_unused_targets(coordinator)
  for rows, err in coordinator:iterate("SELECT id FROM upstreams") do
    if err then
      return nil, err
    end

    for i = 1, #rows do
      local upstream_id = rows[i] and rows[i].id
      if not upstream_id then
        return nil, err
      end

      local _, err = c_clean_repeated_targets(coordinator, upstream_id)
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
      local _, err = pg_remove_unused_targets(connector)
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
