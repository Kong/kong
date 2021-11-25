-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "consumer_groups" (
        "id"          UUID                         PRIMARY KEY,
        "created_at"  TIMESTAMP WITH TIME ZONE     DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "name"        TEXT                         UNIQUE
      );

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "consumer_groups_name_idx" ON "consumer_groups" ("name");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      CREATE TABLE IF NOT EXISTS "consumer_group_plugins" (
        "id"          UUID                         PRIMARY KEY,
        "created_at"  TIMESTAMP WITH TIME ZONE     DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "consumer_group_id"     UUID                         REFERENCES "consumer_groups" ("id") ON DELETE CASCADE,
        "name"        TEXT                         NOT NULL,
        "config"      JSONB                        NOT NULL
      );

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "consumer_group_plugins_group_id_idx" ON "consumer_group_plugins" ("consumer_group_id");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "consumer_group_plugins_plugin_name_idx" ON "consumer_group_plugins" ("name");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      CREATE TABLE IF NOT EXISTS "consumer_group_consumers" (
        "created_at"  TIMESTAMP WITH TIME ZONE     DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "consumer_group_id"     UUID                         REFERENCES "consumer_groups" ("id") ON DELETE CASCADE,
        "consumer_id" UUID                         REFERENCES "consumers" ("id") ON DELETE CASCADE,
        PRIMARY KEY (consumer_group_id, consumer_id)
      );

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "consumer_group_consumers_group_id_idx" ON "consumer_group_consumers" ("consumer_group_id");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "consumer_group_consumers_consumer_id_idx" ON "consumer_group_consumers" ("consumer_id");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      ]],
    },
    cassandra = {
      up = [[
        CREATE TABLE IF NOT EXISTS consumer_groups(
          id          uuid PRIMARY KEY,
          created_at  timestamp,
          name        text
        );

        CREATE INDEX IF NOT EXISTS consumer_groups_name_idx ON consumer_groups(name);

        CREATE TABLE IF NOT EXISTS consumer_group_consumers(
          consumer_id uuid,
          consumer_group_id uuid,
          PRIMARY KEY(consumer_id, consumer_group_id)
        );

        CREATE INDEX IF NOT EXISTS consumer_group_consumers_consumer_id_idx ON consumer_group_consumers(consumer_id);
        CREATE INDEX IF NOT EXISTS consumer_group_consumers_group_id_idx ON consumer_group_consumers(consumer_group_id);

        CREATE TABLE IF NOT EXISTS consumer_group_plugins(
          id          uuid PRIMARY KEY,
          created_at  timestamp,
          consumer_group_id uuid,
          name        text,
          config      text
        );

        CREATE INDEX IF NOT EXISTS consumer_group_plugins_group_id_idx ON consumer_group_plugins(consumer_group_id);
        CREATE INDEX IF NOT EXISTS consumer_group_plugins_plugin_name_idx ON consumer_group_plugins(name);
      ]],
     }
    }
