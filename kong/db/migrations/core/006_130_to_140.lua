return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "upstreams" ADD "host_header" TEXT;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;


      DROP TRIGGER IF EXISTS "delete_expired_cluster_events_trigger" ON "cluster_events";
      DROP FUNCTION IF EXISTS "delete_expired_cluster_events" ();
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
      ALTER TABLE upstreams ADD host_header text;
    ]],
    teardown = function(connector)
      assert(connector:query([[
        DROP INDEX IF EXISTS plugins_run_on_idx;
        ALTER TABLE plugins DROP run_on;


        DROP TABLE IF EXISTS cluster_ca;
      ]]))
    end,
  },
}
