-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "basicauth_credentials" (
        "id"           UUID                         PRIMARY KEY,
        "created_at"   TIMESTAMP WITH TIME ZONE     DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "consumer_id"  UUID                         REFERENCES "consumers" ("id") ON DELETE CASCADE,
        "username"     TEXT                         UNIQUE,
        "password"     TEXT
      );

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "basicauth_consumer_id_idx" ON "basicauth_credentials" ("consumer_id");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS basicauth_credentials (
        id          uuid PRIMARY KEY,
        created_at  timestamp,
        consumer_id uuid,
        password    text,
        username    text
      );
      CREATE INDEX IF NOT EXISTS ON basicauth_credentials(username);
      CREATE INDEX IF NOT EXISTS ON basicauth_credentials(consumer_id);
    ]],
  },
}
