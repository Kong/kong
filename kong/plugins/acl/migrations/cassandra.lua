return {
  {
    name = "2015-08-25-841841_init_acl",
    up = [[
      CREATE TABLE IF NOT EXISTS acls(
        id uuid,
        consumer_id uuid,
        group text,
        created_at timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON acls(group);
      CREATE INDEX IF NOT EXISTS acls_consumer_id ON acls(consumer_id);
    ]],
    down = [[
      DROP TABLE acls;
    ]]
  },
  {
    name = "2018-00-30-000000_add_cache_key_to_acls",
    up = [[
      ALTER TABLE acls ADD cache_key text;
      CREATE INDEX IF NOT EXISTS ON acls(cache_key);
    ]],
    ignore_error = "Invalid column name"
  },
  {
    name = "2018-08-30-000001_fill_in_acls_cache_key",
    up = function(_, _, dao)
      local rows, err = dao.db:query([[
        SELECT * FROM acls;
      ]])
      if err then
        return err
      end
      local len = #rows
      local fmt = string.format
      for i = 1, len do
        local row = rows[i]
        local key = fmt("%s:%s:%s:::",
                        "acls", row.consumer_id or "", row.group or "")
        local cql = fmt("UPDATE acls SET cache_key = '%s' WHERE id = '%s';",
                        key, row.id)
        local _, err = dao.db:query(cql)
        if err then
          return err
        end
      end
    end,
    down = nil
  },

}
