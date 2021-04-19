-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "acls" (
        "id"           UUID                         PRIMARY KEY,
        "created_at"   TIMESTAMP WITH TIME ZONE     DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "consumer_id"  UUID                         REFERENCES "consumers" ("id") ON DELETE CASCADE,
        "group"        TEXT,
        "cache_key"    TEXT                         UNIQUE
      );

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "acls_consumer_id_idx" ON "acls" ("consumer_id");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "acls_group_idx" ON "acls" ("group");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS acls(
        id          uuid PRIMARY KEY,
        created_at  timestamp,
        consumer_id uuid,
        group       text,
        cache_key   text
      );
      CREATE INDEX IF NOT EXISTS ON acls(group);
      CREATE INDEX IF NOT EXISTS ON acls(consumer_id);
      CREATE INDEX IF NOT EXISTS ON acls(cache_key);
    ]],
  },
}
