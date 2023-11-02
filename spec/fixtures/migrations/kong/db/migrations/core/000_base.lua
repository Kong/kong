-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "cluster_events" (
        "id"         UUID                       PRIMARY KEY,
        "node_id"    UUID                       NOT NULL,
        "at"         TIMESTAMP WITH TIME ZONE   NOT NULL,
        "nbf"        TIMESTAMP WITH TIME ZONE,
        "expire_at"  TIMESTAMP WITH TIME ZONE   NOT NULL,
        "channel"    TEXT,
        "data"       TEXT
      );

      CREATE TABLE IF NOT EXISTS "services" (
        "id"    UUID PRIMARY KEY,
        "ws_id" UUID NULL
      );

      CREATE TABLE IF NOT EXISTS "routes" (
        "id"    UUID PRIMARY KEY,
        "ws_id" UUID NULL
      );

      CREATE TABLE IF NOT EXISTS "certificates" (
        "id"    UUID PRIMARY KEY,
        "ws_id" UUID NULL
      );

      CREATE TABLE IF NOT EXISTS "consumers" (
        "id"    UUID PRIMARY KEY,
        "ws_id" UUID NULL
      );

      CREATE TABLE IF NOT EXISTS "snis" (
        "id"    UUID PRIMARY KEY,
        "ws_id" UUID NULL
      );

      CREATE TABLE IF NOT EXISTS "plugins" (
        "id"    UUID PRIMARY KEY,
        "ws_id" UUID NULL
      );

      CREATE TABLE IF NOT EXISTS "upstreams" (
        "id"    UUID PRIMARY KEY,
        "ws_id" UUID NULL
      );

      CREATE TABLE IF NOT EXISTS "targets" (
        "id"    UUID PRIMARY KEY,
        "ws_id" UUID NULL
      );

      CREATE TABLE IF NOT EXISTS "filter_chains" (
        "id"    UUID PRIMARY KEY,
        "ws_id" UUID NULL
      );

      CREATE TABLE IF NOT EXISTS "key_sets" (
        "id"    UUID PRIMARY KEY,
        "ws_id" UUID NULL
      );

      CREATE TABLE IF NOT EXISTS "keys" (
        "id"    UUID PRIMARY KEY,
        "ws_id" UUID NULL
      );

      CREATE TABLE IF NOT EXISTS "sm_vaults" (
        "id"    UUID PRIMARY KEY,
        "ws_id" UUID NULL
      );

      INSERT INTO sm_vaults ("id", "ws_id")
        VALUES ('23111c66-8c80-4f8a-8f18-7d6c495bc36e', '23111c66-8c80-4f8a-8f18-7d6c495bc36e')
      ON CONFLICT DO NOTHING;  -- Hack, mock data

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
    ]]
  },
}
