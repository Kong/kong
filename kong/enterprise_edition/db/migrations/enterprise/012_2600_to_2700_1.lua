-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local log          = require "kong.cmd.utils.log"
local operations = require "kong.enterprise_edition.db.migrations.operations.1500_to_2100"
local ee_new_entities = {
  {
    name = "consumer_groups",
    primary_key = "id",
    uniques = {"name"},
    fks = {},
  }, {
    name = "consumer_group_plugins",
    primary_key = "id",
    uniques = {},
    fks = {{name="consumer_group", reference = "consumer_groups", on_delete = "cascade"}},
  }
}
--------------------------------------------------------------------------------
-- High-level description of the migrations to execute on 'up'
-- @param ops table: table of functions which execute the low-level operations
-- for the database (each function returns a string).
-- @return SQL or CQL
local function ws_migration_up(ops)
  return ops:ws_adjust_fields(ee_new_entities)
end


--------------------------------------------------------------------------------
-- High-level description of the migrations to execute on 'teardown'
-- @param ops table: table of functions which execute the low-level operations
-- for the database (each function receives a connector).
-- @return a function that receives a connector
local function ws_migration_teardown(ops)
  return function(connector)
    ops:drop_run_on(connector)
    log.debug("run_on dropped")

    if ops:has_workspace_entities(connector)[1] then
      ops:ws_adjust_data(connector, ee_new_entities)
      log.debug("adjusted EE data")
    end
  end
end

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
        "cache_key"   TEXT                         UNIQUE,
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
        "cache_key"   TEXT                         UNIQUE,
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

      ]] .. ws_migration_up(operations.postgres.up),
      teardown = ws_migration_teardown(operations.postgres.teardown),
    },
  }
