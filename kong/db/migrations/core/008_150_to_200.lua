return {
  postgres = {
    up = [[
      ALTER TABLE IF EXISTS ONLY "routes" ALTER COLUMN "path_handling" SET DEFAULT 'v0';
    ]],

    teardown = function(connector)
      local _, err = connector:query([[
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
      ]])

      if err then
        return nil, err
      end

      return true
    end,
  },

  cassandra = {
    up = [[
    ]],

    teardown = function(connector)
      local _, err = connector:query([[
        DROP INDEX IF EXISTS plugins_run_on_idx;


        DROP TABLE IF EXISTS cluster_ca;
      ]])

      if err then
        return nil, err
      end

      -- no need to drop the actual column from the database
      -- (this operation is not reentrant in Cassandra)
      --[===[
      assert(connector:query([[
        ALTER TABLE plugins DROP run_on;
      ]]))
      ]===]

      return true
    end,
  },
}
