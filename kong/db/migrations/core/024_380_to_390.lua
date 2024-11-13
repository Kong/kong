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
      CREATE TABLE IF NOT EXISTS clustering_sync_version (
        "version" SERIAL PRIMARY KEY
      );
      CREATE TABLE IF NOT EXISTS clustering_sync_delta (
        "version" INT NOT NULL,
        "type" TEXT NOT NULL,
        "pk" JSON NOT NULL,
        "ws_id" UUID NOT NULL,
        "entity" JSON,
        FOREIGN KEY (version) REFERENCES clustering_sync_version(version) ON DELETE CASCADE
      );
      CREATE INDEX IF NOT EXISTS clustering_sync_delta_version_idx ON clustering_sync_delta (version);
      END;
      $$;
    ]]
  }
}
