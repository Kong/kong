return {
  postgres = {
    up = [[
      DO $$
          BEGIN
          ALTER TABLE IF EXISTS ONLY "plugins" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          ALTER TABLE IF EXISTS ONLY "ca_certificates" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          ALTER TABLE IF EXISTS ONLY "certificates" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          ALTER TABLE IF EXISTS ONLY "consumers" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          ALTER TABLE IF EXISTS ONLY "snis" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          ALTER TABLE IF EXISTS ONLY "targets" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(3) AT TIME ZONE 'UTC');
          ALTER TABLE IF EXISTS ONLY "upstreams" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          ALTER TABLE IF EXISTS ONLY "workspaces" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          ALTER TABLE IF EXISTS ONLY "clustering_data_planes" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
          END;
      $$;
    ]]
  },

  cassandra = {
    up = [[
      ALTER TABLE plugins ADD updated_at timestamp;
      ALTER TABLE ca_certificates ADD updated_at timestamp;
      ALTER TABLE certificates ADD updated_at timestamp;
      ALTER TABLE consumers ADD updated_at timestamp;
      ALTER TABLE snis ADD updated_at timestamp;
      ALTER TABLE targets ADD updated_at timestamp;
      ALTER TABLE upstreams ADD updated_at timestamp;
      ALTER TABLE workspaces ADD updated_at timestamp;
      ALTER TABLE clustering_data_planes ADD updated_at timestamp;
    ]]
  },
}
