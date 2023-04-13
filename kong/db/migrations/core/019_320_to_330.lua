-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
    up = [[
      DO $$
          BEGIN
          ALTER TABLE IF EXISTS ONLY "plugins" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
          END;
      $$;

      DO $$
          BEGIN
          ALTER TABLE IF EXISTS ONLY "ca_certificates" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
          END;
      $$;

      DO $$
          BEGIN
          ALTER TABLE IF EXISTS ONLY "certificates" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
          END;
      $$;

      DO $$
          BEGIN
          ALTER TABLE IF EXISTS ONLY "consumers" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
          END;
      $$;

      DO $$
          BEGIN
          ALTER TABLE IF EXISTS ONLY "snis" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
          END;
      $$;

      DO $$
          BEGIN
          ALTER TABLE IF EXISTS ONLY "targets" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(3) AT TIME ZONE 'UTC');
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
          END;
      $$;

      DO $$
          BEGIN
          ALTER TABLE IF EXISTS ONLY "upstreams" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
          END;
      $$;

      DO $$
          BEGIN
          ALTER TABLE IF EXISTS ONLY "workspaces" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
          END;
      $$;

      DO $$
          BEGIN
          ALTER TABLE IF EXISTS ONLY "clustering_data_planes" ADD "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC');
          EXCEPTION WHEN DUPLICATE_COLUMN THEN
            -- Do nothing, accept existing state
          END;
      $$;

      CREATE OR REPLACE FUNCTION batch_delete_expired_rows() RETURNS trigger
      LANGUAGE plpgsql
      AS $$
        BEGIN
          EXECUTE FORMAT('WITH rows AS (SELECT ctid FROM %s WHERE %s < CURRENT_TIMESTAMP AT TIME ZONE ''UTC'' ORDER BY %s LIMIT 2 FOR UPDATE SKIP LOCKED) DELETE FROM %s WHERE ctid IN (TABLE rows)', TG_TABLE_NAME, TG_ARGV[0], TG_ARGV[0], TG_TABLE_NAME);
          RETURN NULL;
        END;
      $$;

      DROP TRIGGER IF EXISTS "cluster_events_ttl_trigger" ON "cluster_events";

      DO $$
      BEGIN
        CREATE TRIGGER "cluster_events_ttl_trigger"
        AFTER INSERT ON "cluster_events"
        FOR EACH STATEMENT
        EXECUTE PROCEDURE batch_delete_expired_rows("expire_at");
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;


      DROP TRIGGER IF EXISTS "clustering_data_planes_ttl_trigger" ON "clustering_data_planes";

      DO $$
      BEGIN
        CREATE TRIGGER "clustering_data_planes_ttl_trigger"
        AFTER INSERT ON "clustering_data_planes"
        FOR EACH STATEMENT
        EXECUTE PROCEDURE batch_delete_expired_rows("ttl");
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;
    ]],
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
