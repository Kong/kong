return {
  {
    name = "2015-08-25-841841_init_acl",
    up = [[
      CREATE TABLE IF NOT EXISTS acls(
        id uuid,
        consumer_id uuid REFERENCES consumers (id) ON DELETE CASCADE,
        "group" text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('acls_group')) IS NULL THEN
          CREATE INDEX acls_group ON acls("group");
        END IF;
        IF (SELECT to_regclass('acls_consumer_id')) IS NULL THEN
          CREATE INDEX acls_consumer_id ON acls(consumer_id);
        END IF;
      END$$;
    ]],
    down = [[
      DROP TABLE acls;
    ]]
  },
  {
    name = "2018-08-30-000001_acls_add_cache_key_column",
    up = [[
      DO $$
      BEGIN
        ALTER TABLE acls ADD COLUMN cache_key text UNIQUE;
      EXCEPTION WHEN duplicate_column THEN
          -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        IF (SELECT to_regclass('acls_cache_key_idx')) IS NULL THEN
          CREATE INDEX acls_cache_key_idx ON acls(cache_key);
        END IF;
      END$$;
    ]],
    down = nil,
  },
  {
    name = "2018-08-30-000000_fill_in_acls_cache_key",
    up = function(_, _, dao)
      local rows, err = dao.db:query([[
        SELECT * FROM acls;
      ]])
      if err then
        return err
      end
      local sql_buffer = { "BEGIN;" }
      local len = #rows
      local fmt = string.format
      for i = 1, len do
        local row = rows[i]
        local key = fmt("%s:%s:%s:::",
                        "acls", row.consumer_id or "", row.group or "")
        sql_buffer[i + 1] = fmt("UPDATE acls SET cache_key = '%s' WHERE id = '%s';",
                                key, row.id)
      end
      sql_buffer[len + 2] = "COMMIT;"

      local _, err = dao.db:query(table.concat(sql_buffer, "\n"))
      if err then
        return err
      end
    end,
    down = nil
  },
}
