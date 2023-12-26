-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local utils = require "kong.tools.utils"
local enums = require "kong.enterprise_edition.dao.enums"

local fmt = string.format

-- This query is designed to ensure that the workspace entity counter does not count non-proxy
-- consumers. The created consumer may not function as expected.
-- See also: `seed()` in kong/enterprise_edition/db/migrations/enterprise/000_base.lua
local mock_admin_consumer = [[
    DO $$
    BEGIN
      -- Mainly taken from enterprise base migration
      IF not EXISTS (SELECT column_name
            FROM information_schema.columns
            WHERE table_schema=current_schema()
              AND table_name='consumers'
              AND column_name='type') THEN
        ALTER TABLE consumers ADD COLUMN type int NOT NULL DEFAULT 0;
      END IF;
    END$$;
]] .. fmt([[
  INSERT INTO consumers (id, ws_id, type) VALUES ('%s', '%s', %d);
]], utils.uuid(), utils.uuid(), enums.CONSUMERS.TYPE.ADMIN)

return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "workspaces" (
        id  UUID                  PRIMARY KEY,
        name                      TEXT                      UNIQUE,
        comment                   TEXT,
        created_at                TIMESTAMP WITHOUT TIME ZONE DEFAULT timezone('utc'::text, ('now'::text)::timestamp(0) with time zone),
        meta                      JSON                      DEFAULT '{}'::json,
        config                    JSON                      DEFAULT '{"portal":false}'::json
      );

      CREATE TABLE IF NOT EXISTS "workspace_entity_counters" (
        workspace_id uuid,
        entity_type text,
        count int,
        PRIMARY KEY(workspace_id, entity_type)
      );

      CREATE TABLE IF NOT EXISTS "rbac_users" (
        "id"    UUID PRIMARY KEY,
        "ws_id" UUID NULL
      );

      CREATE TABLE IF NOT EXISTS "rbac_roles" (
        "id"    UUID PRIMARY KEY,
        "ws_id" UUID NULL
      );

      CREATE TABLE IF NOT EXISTS "consumer_groups" (
        "id"    UUID PRIMARY KEY,
        "ws_id" UUID NULL
      );

      CREATE TABLE IF NOT EXISTS "consumer_group_plugins" (
        "id"    UUID PRIMARY KEY,
        "ws_id" UUID NULL
      );

      CREATE TABLE IF NOT EXISTS "files" (
        "id"    UUID PRIMARY KEY,
        "ws_id" UUID NULL
      );

      CREATE TABLE IF NOT EXISTS "developers" (
        "id"    UUID PRIMARY KEY,
        "ws_id" UUID NULL
      );

      CREATE TABLE IF NOT EXISTS "document_objects" (
        "id"    UUID PRIMARY KEY,
        "ws_id" UUID NULL
      );

      CREATE TABLE IF NOT EXISTS "applications" (
        "id"    UUID PRIMARY KEY,
        "ws_id" UUID NULL
      );

      CREATE TABLE IF NOT EXISTS "application_instances" (
        "id"    UUID PRIMARY KEY,
        "ws_id" UUID NULL
      );
    ]] .. mock_admin_consumer
  },
}
