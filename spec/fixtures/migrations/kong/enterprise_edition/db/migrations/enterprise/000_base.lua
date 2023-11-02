-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
    ]]
  },
}
