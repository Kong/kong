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
  },

  cassandra = {
    up = [[
      ALTER TABLE upstreams ADD host_header text;
    ]],
  },
}
