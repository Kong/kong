local rbac_migrations_defaults = require "kong.rbac.migrations.01_defaults"
local rbac_migrations_user_default_role = require "kong.rbac.migrations.03_user_default_role"
local rbac_migrations_super_admin = require "kong.rbac.migrations.05_super_admin"
local files = require "kong.portal.migrations.01_initial_files"
local fmt = string.format
local utils = require "kong.tools.utils"
local pgmoon = require "pgmoon"


return {
  {
    name = "2018-04-20-122000_rbac_defaults",
    up = function(_, _, dao)
      return rbac_migrations_defaults.up(nil, nil, dao)
    end
  },
  {
    name = "2018-04-20-122000_rbac_user_default_roles",
    up = function(_, _, dao)
      return rbac_migrations_user_default_role.up(nil, nil, dao)
    end
  },
  {
    name = "2018-04-25-000001_portal_initial_files",
    up = function(_, _, dao)

      local INSERT_FILE = [[
        INSERT INTO portal_files(id, auth, name, type, contents)
        VALUES(%s, %s, %s, %s, %s)
        ON CONFLICT DO NOTHING
      ]]

      -- Iterate over file list and insert files that do not exist
      for _, file in ipairs(files) do
        local id       = pgmoon.Postgres.escape_literal(nil, utils.uuid())
        local auth     = pgmoon.Postgres.escape_literal(nil, file.auth)
        local name     = pgmoon.Postgres.escape_literal(nil, file.name)
        local type     = pgmoon.Postgres.escape_literal(nil, file.type)
        local contents = pgmoon.Postgres.escape_literal(nil, file.contents)

        local q = fmt(INSERT_FILE, id, auth, name, type, contents)

        local _, err = dao.db:query(q)
        if err then
          return nil, err
        end
      end
    end,
  },
  {
    name = "2018-04-10-094800_dev_portal_consumer_types_statuses",
    up = [[
      CREATE TABLE IF NOT EXISTS consumer_statuses (
        id               int PRIMARY KEY,
        name 			       text NOT NULL,
        comment 		     text,
        created_at       timestamp without time zone DEFAULT timezone('utc'::text, ('now'::text)::timestamp(0) with time zone)
      );

      CREATE TABLE IF NOT EXISTS consumer_types (
        id               int PRIMARY KEY,
        name 			       text NOT NULL,
        comment 		     text,
        created_at       timestamp without time zone DEFAULT timezone('utc'::text, ('now'::text)::timestamp(0) with time zone)
      );

      CREATE INDEX IF NOT EXISTS consumer_statuses_names_idx
          ON consumer_statuses (name);

      CREATE INDEX IF NOT EXISTS consumer_types_name_idx
          ON consumer_types (name);
    ]],

    down = [[
      DROP TABLE consumer_statuses;
      DROP TABLE consumer_types;
      DROP INDEX consumer_statuses_names_idx;
      DROP INDEX consumer_types_name_idx;
    ]]
  },
  {
    name = "2018-04-10-094800_consumer_type_status_defaults",
    up = function(_, _, dao)
      local helper = require('kong.portal.dao_helpers')
      return helper.register_resources(dao)
    end,

    down = [[
      DELETE FROM consumer_statuses;
      DELETE FROM consumer_types;
    ]]
  },
  {
    name = "2018-05-08-143700_consumer_dev_portal_columns",
    up = [[
      ALTER TABLE consumers
        ADD COLUMN type int NOT NULL DEFAULT 0 REFERENCES consumer_types (id),
        ADD COLUMN email text,
        ADD COLUMN status integer REFERENCES consumer_statuses (id),
        ADD COLUMN meta text;

      ALTER TABLE consumers ADD CONSTRAINT consumers_email_type_key UNIQUE(email, type);

      CREATE INDEX IF NOT EXISTS consumers_type_idx
          ON consumers (type);

      CREATE INDEX IF NOT EXISTS consumers_status_idx
          ON consumers (status);
    ]],

    down = [[
      DROP INDEX consumers_type_idx;
      DROP INDEX consumers_status_idx;
      ALTER TABLE consumers DROP CONSTRAINT consumers_email_type_key;
      ALTER TABLE consumers DROP COLUMN type;
      ALTER TABLE consumers DROP COLUMN email;
      ALTER TABLE consumers DROP COLUMN status;
      ALTER TABLE consumers DROP COLUMN meta;
    ]]
  },
  {
    name = "2018-05-03-120000_credentials_master_table",
    up = [[
      CREATE TABLE IF NOT EXISTS credentials (
        id                uuid PRIMARY KEY,
        consumer_id       uuid REFERENCES consumers (id) ON DELETE CASCADE,
        consumer_type     integer REFERENCES consumer_types (id),
        plugin            text NOT NULL,
        credential_data   json,
        created_at        timestamp without time zone DEFAULT timezone('utc'::text, ('now'::text)::timestamp(0) with time zone)
      );

      CREATE INDEX IF NOT EXISTS credentials_consumer_type
        ON credentials (consumer_id);

      CREATE INDEX IF NOT EXISTS credentials_consumer_id_plugin
        ON credentials (consumer_id, plugin);
    ]],

    down = [[
      DROP TABLE credentials
    ]]
  },
  {
    name = "2017-05-15-110000_vitals_locks",
    up = [[
      CREATE TABLE IF NOT EXISTS vitals_locks(
        key text,
        expiry timestamp with time zone,
        PRIMARY KEY(key)
      );
      INSERT INTO vitals_locks(key, expiry)
      VALUES ('delete_status_codes', NULL);
    ]],
    down = [[
      DROP TABLE vitals_locks;
    ]]
  },
  {
    name = "2018-03-12-000000_vitals_v0.33",
    up = [[
      CREATE INDEX IF NOT EXISTS vcbr_svc_ts_idx
      ON vitals_codes_by_route(service_id, duration, at);
    ]],
  },
  {
    name = "2018-06-12-105400_consumers_rbac_users_mapping",
    up = [[
      CREATE TABLE IF NOT EXISTS consumers_rbac_users_map(
        consumer_id uuid REFERENCES consumers (id) ON DELETE CASCADE,
        user_id uuid REFERENCES rbac_users (id) ON DELETE CASCADE,
        created_at timestamp without time zone DEFAULT timezone('utc'::text, ('now'::text)::timestamp(0) with time zone),
        PRIMARY KEY (consumer_id, user_id)
      );
    ]],
    down = [[
      DROP TABLE consumers_rbac_users_map;
    ]]
  },
  {
    name = "2018-06-12-076222_consumer_type_status_admin",
    up = [[
      INSERT INTO consumer_types(id, name, comment)
      VALUES (2, 'admin', 'Admin consumer.')
      ON CONFLICT DO NOTHING;
    ]],
    down = [[
      DELETE FROM consumer_types;
    ]]
  },
  {
    name = "2018-07-30-038822_remove_old_vitals_tables",
    up = [[
      DROP TABLE vitals_codes_by_service;
      DROP TABLE vitals_consumers;
    ]]
  },
  {
    name = "2018-08-07-114500_consumer_reset_secrets",
    up = [[
      CREATE TABLE IF NOT EXISTS token_statuses(
        id integer PRIMARY KEY,
        name text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );

      CREATE INDEX IF NOT EXISTS token_statuses_name
      ON token_statuses (name);

      INSERT INTO token_statuses(id, name)
      VALUES (1, 'pending')
      ON CONFLICT DO NOTHING;

      INSERT INTO token_statuses(id, name)
      VALUES (2, 'consumed')
      ON CONFLICT DO NOTHING;

      INSERT INTO token_statuses(id, name)
      VALUES (3, 'invalidated')
      ON CONFLICT DO NOTHING;

      CREATE TABLE IF NOT EXISTS consumer_reset_secrets(
        id uuid PRIMARY KEY,
        consumer_id uuid REFERENCES consumers (id) ON DELETE CASCADE,
        secret text,
        status integer REFERENCES token_statuses (id),
        client_addr text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        updated_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );

      CREATE INDEX IF NOT EXISTS consumer_reset_secrets_consumer_id
      ON consumer_reset_secrets(consumer_id);

      CREATE INDEX IF NOT EXISTS consumer_reset_secrets_status
      ON consumer_reset_secrets(status);
    ]],
    down = [[
      DROP TABLE consumer_reset_secrets;
      DROP TABLE token_statuses;
    ]]
  },
  {
    name = "2018-08-14-000000_vitals_workspaces",
    up = [[
      CREATE TABLE IF NOT EXISTS vitals_code_classes_by_workspace(
        workspace_id uuid,
        code_class int,
        at timestamp with time zone,
        duration int,
        count int,
        PRIMARY KEY (workspace_id, code_class, duration, at)
      );
    ]],
  },
  {
    name = "2018-09-05-144800_workspace_meta",
    up = [[
      ALTER TABLE workspaces
        ADD COLUMN meta json DEFAULT '{}';
    ]]
  },
  {
    name = "2018-10-03-120000_audit_requests_init",
    up = [[
      CREATE TABLE IF NOT EXISTS audit_requests(
        request_id char(32) PRIMARY KEY,
        request_timestamp timestamp without time zone default (CURRENT_TIMESTAMP(3) at time zone 'utc'),
        client_ip text NOT NULL,
        path text NOT NULL,
        method text NOT NULL,
        payload text,
        status integer NOT NULL,
        rbac_user_id uuid,
        workspace uuid,
        signature text,
        expire timestamp without time zone
      );

      DO $$
      BEGIN
          IF (SELECT to_regclass('idx_audit_requests_expire')) IS NULL THEN
              CREATE INDEX idx_audit_requests_expire on audit_requests(expire);
          END IF;
      END$$;

      CREATE OR REPLACE FUNCTION delete_expired_audit_requests() RETURNS trigger
          LANGUAGE plpgsql
          AS $$
      BEGIN
          DELETE FROM audit_requests WHERE expire <= NOW();
          RETURN NEW;
      END;
      $$;

      DO $$
      BEGIN
          IF NOT EXISTS(
              SELECT FROM information_schema.triggers
               WHERE event_object_table = 'audit_requests'
                 AND trigger_name = 'deleted_expired_audit_requests_trigger')
          THEN
              CREATE TRIGGER delete_expired_audit_requests_trigger
               AFTER INSERT on audit_requests
               EXECUTE PROCEDURE delete_expired_audit_requests();
          END IF;
      END;
      $$;
    ]],
    down = [[
      DROP TABLE audit_requests;
    ]],
  },
  {
    name = "2018-10-03-120000_audit_objects_init",
    up = [[
      CREATE TABLE IF NOT EXISTS audit_objects(
        id uuid PRIMARY KEY,
        request_id char(32),
        entity_key uuid,
        dao_name text NOT NULL,
        operation char(6) NOT NULL,
        entity text,
        rbac_user_id uuid,
        signature text,
        expire timestamp without time zone
      );

      DO $$
      BEGIN
          IF (SELECT to_regclass('idx_audit_objects_expire')) IS NULL THEN
              CREATE INDEX idx_audit_objects_expire on audit_objects(expire);
          END IF;
      END$$;

      CREATE OR REPLACE FUNCTION delete_expired_audit_objects() RETURNS trigger
          LANGUAGE plpgsql
          AS $$
      BEGIN
          DELETE FROM audit_objects WHERE expire <= NOW();
          RETURN NEW;
      END;
      $$;

      DO $$
      BEGIN
          IF NOT EXISTS(
              SELECT FROM information_schema.triggers
               WHERE event_object_table = 'audit_objects'
                 AND trigger_name = 'deleted_expired_audit_objects_trigger')
          THEN
              CREATE TRIGGER delete_expired_audit_objects_trigger
               AFTER INSERT on audit_objects
               EXECUTE PROCEDURE delete_expired_audit_objects();
          END IF;
      END;
      $$;
    ]],
    down = [[
      DROP TABLE audit_objects;
    ]]
  },
  {
    name = "2018-10-05-144800_workspace_config",
    up = [[
      ALTER TABLE workspaces
        ADD COLUMN config json DEFAULT '{"portal":false}';
      UPDATE workspaces SET config = '{"portal":true}' WHERE name = 'default';
    ]]
  },
  {
    name = "2018-10-09-095247_create_entity_counters_table",
    up = [[
      CREATE TABLE IF NOT EXISTS workspace_entity_counters(
      workspace_id uuid REFERENCES workspaces (id) ON DELETE CASCADE,
      entity_type text,
      count int,
      PRIMARY KEY(workspace_id, entity_type)
    );
  ]],
    down = [[
      DROP TABLE workspace_entity_counters;
  ]]
  },
  {
    name = "2018-10-17-160000_nested_workspaces_cleanup",
    up = [[
      DELETE FROM workspace_entities WHERE entity_type = 'workspaces'
    ]]
  },
  {
    name = "2018-10-17-170000_portal_files_to_files",
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS portal_files RENAME TO files;
      EXCEPTION WHEN duplicate_table THEN
         -- Do nothing, accept existing state
      END$$;
    ]]
  },
  {
    name = "2018-10-24-000000_upgrade_admins",
    up = [[
      UPDATE consumers
         SET status = 0
       WHERE type = 2
    ]]
  },
  {
    name = "2018-11-30-000000_case_insensitive_email",
    up = [[
      UPDATE consumers
         SET email = LOWER(email)
       WHERE type = 2
    ]]
  },
  {
    name = "2018-12-13-100000_rbac_token_hash",
    up = [[
      ALTER TABLE rbac_users ADD COLUMN user_token_ident text;

      DO $$
      BEGIN
          IF (SELECT to_regclass('idx_rbac_token_ident')) IS NULL THEN
              CREATE INDEX idx_rbac_token_ident on rbac_users(user_token_ident);
          END IF;
      END$$;
    ]],
  },
  {
    name = "2018-12-23-110000_rbac_user_super_admin",
    up = function(_, _, dao)
      return rbac_migrations_super_admin.up(nil, nil, dao)
    end
  },
}
