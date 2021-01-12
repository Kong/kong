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
      -- update shape in all foos
      for row, err in connector:iterate('SELECT * FROM "foos";') do
        if err then
          return nil, err
        end

        local shape = "triangle"
        local sql = string.format([[
          UPDATE "foos" SET "shape" = '%s' WHERE "color" = '%s';
        ]], shape, row.color)
        assert(connector:query(sql))
      end


      -- check insertion and update
      local count = 0
      for row, err in connector:iterate('SELECT * FROM "foos";') do
        if err then
          return nil, err
        end

        count = count + 1
        assert(row.color == "red", "Wrong color: " .. tostring(row.color))
        assert(row.shape == "triangle", "Wrong shape: " .. tostring(row.shape))
      end

      assert(count == 1, "Expected 1 foo, found " .. tostring(count))

      return true
    end,
  },

  cassandra = {
    up = [[
      ALTER TABLE foos ADD shape text;
      CREATE INDEX IF NOT EXISTS foos_shape_idx ON foos(shape);
    ]],
    up_f = function(connector)
      local coordinator = assert(connector:get_stored_connection())
      local _, err = coordinator:execute([[
        INSERT INTO foos(color) values('blue');
      ]])

      if err then
        return nil, err
      end

      return true
    end,

    teardown = function(connector, _)
      local coordinator = assert(connector:get_stored_connection())
      -- Update: assing shape=triangle to all foos
      for rows, err in coordinator:iterate("SELECT * FROM foos") do
        if err then
          return nil, err
        end

        for _, row in ipairs(rows) do
          local shape = "triangle"
          local cql = string.format([[
            UPDATE foos SET shape = '%s' WHERE color = '%s'
          ]], shape, row.color)
          assert(coordinator:execute(cql))
        end
      end

      -- final check of insertions/updates
      local count = 0
      for rows, err in coordinator:iterate("SELECT * FROM foos") do
        if err then
          return nil, err
        end

        for _, row in ipairs(rows) do
          count = count + 1
          assert(row.shape == "triangle", "Wrong shape: " .. tostring(row.shape))
          local c = row.color
          assert(
            c == "red" or c == "green" or c == "blue",
            "Wrong color: " .. tostring(c))
        end
      end
      assert(count == 3, "Expected 3 foos, found " .. tostring(count))

      return true
    end,
  },
}
