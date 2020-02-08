return {
  postgres = {
    up = [[
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
    ]],

    teardown = function(connector)
      assert(connector:query([[
        DROP INDEX IF EXISTS plugins_run_on_idx;


        DROP TABLE IF EXISTS cluster_ca;
      ]]))

      -- no need to drop the actual row from the database
      -- (this operation is not reentrant in Cassandra)
      --[===[
      assert(connector:query([[
        ALTER TABLE plugins DROP run_on;
      ]]))
      ]===]
    end,
  },
}
