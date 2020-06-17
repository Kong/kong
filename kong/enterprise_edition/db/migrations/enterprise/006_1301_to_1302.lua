return {
  postgres = {
    up = [[

      DROP TRIGGER IF EXISTS "delete_expired_cluster_events_trigger" ON "cluster_events";
      DROP FUNCTION IF EXISTS "delete_expired_cluster_events" ();
    ]],

  },

  cassandra = {
    up = [[

    ]],
  },

}
