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
}
