return {
  postgres = {
    up = [[

    ]],
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
