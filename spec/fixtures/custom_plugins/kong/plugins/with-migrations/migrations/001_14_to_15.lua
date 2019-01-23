return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "foos" ADD "shape" TEXT UNIQUE;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;
    ]],

    teardown = function(connector, _)
      assert(connector:connect_migrations())

      for rows, err in connector:iterate('SELECT * FROM "foos";') do
        if err then
          return nil, err
        end

        for _, row in ipairs(rows) do
          local shape = "triangle"
          local sql = string.format([[
            UPDATE "foos" SET "shape" = '%s' WHERE "color" = '%s';
          ]], shape, row.color)
          assert(connector:query(sql))
        end
      end
    end,
  },

  cassandra = {
    up = [[
      ALTER TABLE foos ADD shape text;
      CREATE INDEX IF NOT EXISTS foos_shape_idx ON foos(shape);
    ]],

    teardown = function(connector, _)
      local coordinator = assert(connector:connect_migrations())

      for rows, err in coordinator:iterate("SELECT * FROM foos") do
        if err then
          return nil, err
        end

        for _, row in ipairs(rows) do
          local shape = "triangle"
          local cql = string.format([[
            UPDATE foos SET shape = '%s' WHERE color = '%s'
          ]], shape, row.color)
          assert(connector:query(cql))
        end
      end
    end,
  },
}
