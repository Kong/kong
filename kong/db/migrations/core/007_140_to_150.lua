return {
  postgres = {
    up = [[
      -- If migrating from 1.x, the "path_handling" column does not exist yet.
      -- Create it with a default of 'v1' to fill existing rows.
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "routes" ADD "path_handling" TEXT DEFAULT 'v1';
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;
    ]],
  },

  cassandra = {
    up = [[
      ALTER TABLE routes ADD path_handling text;
    ]],

    teardown = function(connector)
      local coordinator = assert(connector:connect_migrations())

      for rows, err in coordinator:iterate([[SELECT * FROM routes]]) do
        if err then
          return nil, err
        end

        for _, row in ipairs(rows) do
          if row.path_handling ~= "v0" then
            assert(connector:query([[
              UPDATE routes SET path_handling = 'v1'
              WHERE partition = 'routes' AND id = ]] .. row.id))
          end
        end
      end
    end,
  },
}
