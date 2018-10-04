return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "acls" ADD "cache_key" TEXT UNIQUE;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      ALTER TABLE IF EXISTS ONLY "acls"
        ALTER "created_at" TYPE TIMESTAMP WITH TIME ZONE USING "created_at" AT TIME ZONE 'UTC',
        ALTER "created_at" SET DEFAULT CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC';

      ALTER INDEX IF EXISTS "acls_consumer_id" RENAME TO "acls_consumer_id_idx";
      ALTER INDEX IF EXISTS "acls_group"       RENAME TO "acls_group_idx";
    ]],

    teardown = function(connector, helpers)
      assert(connector:connect_migrations())

      for rows, err in connector:iterate('SELECT * FROM "acls" ORDER BY "created_at";') do
        if err then
          return nil, err
        end

        for i = 1, #rows do
          local row = rows[i]
          local cache_key = string.format("%s:%s:%s:::", "acls",
                                          row.consumer_id or "",
                                          row.group or "")

          local sql = string.format([[
            UPDATE "acls" SET "cache_key" = '%s' WHERE "id" = '%s';
          ]], cache_key, row.id)

          assert(connector:query(sql))
        end
      end
    end,
  },

  cassandra = {
    up = [[
      ALTER TABLE acls ADD cache_key text;
      CREATE INDEX IF NOT EXISTS acls_cache_key_idx ON acls(cache_key);
    ]],

    teardown = function(connector, helpers)
      local coordinator = assert(connector:connect_migrations())

      for rows, err in coordinator:iterate("SELECT * FROM acls") do
        if err then
          return nil, err
        end

        for i = 1, #rows do
          local row = rows[i]
          local cache_key = string.format("%s:%s:%s:::", "acls",
                                          row.consumer_id or "",
                                          row.group or "")

          local cql = string.format([[
            UPDATE acls SET cache_key = '%s' WHERE id = '%s'
          ]], cache_key, row.id)

          assert(connector:query(cql))
        end
      end
    end,
  },
}
