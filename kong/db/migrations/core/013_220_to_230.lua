-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local uuid = require("kong.tools.uuid")


local CLUSTER_ID = uuid.uuid()


return {
  postgres = {
    up = string.format([[
      CREATE TABLE IF NOT EXISTS "parameters" (
        key            TEXT PRIMARY KEY,
        value          TEXT NOT NULL,
        created_at     TIMESTAMP WITH TIME ZONE
      );

      INSERT INTO parameters (key, value) VALUES('cluster_id', '%s')
      ON CONFLICT DO NOTHING;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "certificates" ADD "cert_alt" TEXT;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "certificates" ADD "key_alt" TEXT;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "clustering_data_planes" ADD "version" TEXT;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "clustering_data_planes" ADD "sync_status" TEXT NOT NULL DEFAULT 'unknown';
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;
    ]], CLUSTER_ID),
  },
}
