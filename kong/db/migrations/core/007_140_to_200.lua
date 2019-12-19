return {
  postgres = {
    up = [[
      -- If migrating from 1.x, the "path_handling" column does not exist yet.
      -- Create it with a default of 'v1' to fill existing rows, then change the default.
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "routes" ADD "path_handling" TEXT DEFAULT 'v1';
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;
      ALTER TABLE IF EXISTS ONLY "routes" ALTER COLUMN "path_handling" SET DEFAULT 'v0';
    ]],

    teardown = function(connector)
      assert(connector:query([[
        DO $$
        BEGIN
          ALTER TABLE IF EXISTS ONLY "plugins" DROP COLUMN "run_on";
        EXCEPTION WHEN UNDEFINED_COLUMN THEN
          -- Do nothing, accept existing state
        END;
        $$;


        DO $$
        BEGIN
          DROP TABLE IF EXISTS "cluster_ca";
        END;
        $$;
      ]]))
    end,
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

      assert(connector:query([[
        DROP INDEX IF EXISTS plugins_run_on_idx;
        ALTER TABLE plugins DROP run_on;


        DROP TABLE IF EXISTS cluster_ca;
      ]]))
    end,
  },
}
