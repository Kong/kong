local rbac = require "kong.rbac"
local utils = require "kong.tools.utils"
local bit = require "bit"


local bor = bit.bor


return {
  {
    name = "2017-06-20-100000_init_ratelimiting",
    up = [[
      CREATE TABLE IF NOT EXISTS rl_counters(
        key          text,
        namespace    text,
        window_start int,
        window_size  int,
        count        int,
        PRIMARY KEY(key, namespace, window_start, window_size)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('sync_key_idx')) IS NULL THEN
          CREATE INDEX sync_key_idx ON rl_counters(namespace, window_start);
        END IF;
      END$$;
    ]],
    down = [[
      DROP TABLE rl_counters;
    ]],
  },
  {
    name = "2017-07-31-993505_vitals_stats_seconds",
    up = [[
      CREATE TABLE IF NOT EXISTS vitals_stats_seconds(
          at integer,
          l2_hit integer default 0,
          l2_miss integer default 0,
          plat_min integer,
          plat_max integer,
          PRIMARY KEY (at)
      );
    ]],
    down = [[
      DROP TABLE vitals_stats_seconds;
    ]]
  },
  {
    name = "2017-08-30-892844_vitals_stats_minutes",
    up = [[
      CREATE TABLE IF NOT EXISTS vitals_stats_minutes(
          at integer,
          l2_hit integer default 0,
          l2_miss integer default 0,
          plat_min integer,
          plat_max integer,
          PRIMARY KEY (at)
      );
    ]],
    down = [[
      DROP TABLE vitals_stats_minutes;
    ]]
  },
  {
    name = "2017-08-30-892844_vitals_stats_hours",
    up = [[
      CREATE TABLE IF NOT EXISTS vitals_stats_hours(
          at integer,
          l2_hit integer default 0,
          l2_miss integer default 0,
          plat_min integer,
          plat_max integer,
          PRIMARY KEY (at)
      );
    ]],
    down = [[
      DROP TABLE vitals_stats_hours;
    ]]
  },
--  recreate vitals tables with new primary key to support node-level stats
  {
    name = "2017-10-31-145721_vitals_stats_v0.30",
    up = function(_, _, dao)
      local vitals = require("kong.vitals")

      -- drop all vitals tables, including generated ones
      local table_names   = vitals.table_names(dao)
      local allowed_chars = "^vitals_[a-zA-Z0-9_]+$"
      for _, v in ipairs(table_names) do
        if not v:match(allowed_chars) then
          return "illegal table name " .. v
        end

        local _, err = dao.db:query(string.format("drop table if exists %s", v))

        -- bail on first error
        if err then
          return err
        end
      end

      local _, err = dao.db:query([[
        CREATE TABLE vitals_stats_seconds(
          node_id uuid,
          at integer,
          l2_hit integer default 0,
          l2_miss integer default 0,
          plat_min integer,
          plat_max integer,
          ulat_min integer,
          ulat_max integer,
          requests integer default 0,
          PRIMARY KEY (node_id, at)
        );
      ]])

      if err then
        return err
      end

      local _, err = dao.db:query([[
        CREATE TABLE vitals_stats_minutes
        (LIKE vitals_stats_seconds INCLUDING defaults INCLUDING constraints INCLUDING indexes);
      ]])

      if err then
        return err
      end
    end,
    down = [[
      DROP TABLE vitals_stats_seconds;
      DROP TABLE vitals_stats_minutes;
    ]]
  },
  {
    name = "2017-10-31-145722_vitals_node_meta",
    up = [[
      CREATE TABLE IF NOT EXISTS vitals_node_meta(
        node_id uuid PRIMARY KEY,
        first_report timestamp without time zone,
        last_report timestamp without time zone,
        hostname text
      );
    ]],
    down = [[
      DROP TABLE vitals_node_meta;
    ]]
  },
  {
    name = "2017-11-13-145723_vitals_consumers",
    up = [[
      CREATE TABLE IF NOT EXISTS vitals_consumers(
        consumer_id uuid,
        node_id uuid,
        at timestamp with time zone,
        duration integer,
        count integer,
        PRIMARY KEY(consumer_id, node_id, at, duration)
      );
    ]],
    down = [[
      DROP TABLE vitals_consumers;
    ]]
  },
  {
    name = "2018-01-12-110000_workspaces",
    up = [[
      CREATE TABLE IF NOT EXISTS workspaces(
        id uuid PRIMARY KEY,
        name text UNIQUE NOT NULL,
        comment text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );

      CREATE TABLE IF NOT EXISTS workspace_entities(
        workspace_id uuid,
        entity_id text,
        entity_type text,
        unique_field_name text,
        unique_field_value text,
        PRIMARY KEY(workspace_id, entity_id, unique_field_name)
      );

    ]],
    down = [[
      DROP TABLE IF EXISTS workspaces;
    ]],
  },
  {
    name = "2018-04-18-110000_old_rbac_cleanup",
    up = [[
      DROP TABLE IF EXISTS rbac_users;
      DROP TABLE IF EXISTS rbac_users_roles;
      DROP TABLE IF EXISTS rbac_roles;
      DROP TABLE IF EXISTS rbac_perms;
      DROP TABLE IF EXISTS rbac_role_perms;
      DROP TABLE IF EXISTS rbac_resources;
    ]]
  },
  {
    name = "2018-04-20-160000_rbac",
    up = [[
      CREATE TABLE IF NOT EXISTS rbac_users(
        id uuid PRIMARY KEY,
        name text UNIQUE NOT NULL,
        user_token text UNIQUE NOT NULL,
        comment text,
        enabled boolean NOT NULL,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('rbac_users_name_idx')) IS NULL THEN
          CREATE INDEX rbac_users_name_idx on rbac_users(name);
        END IF;
        IF (SELECT to_regclass('rbac_users_token_idx')) IS NULL THEN
          CREATE INDEX rbac_users_token_idx on rbac_users(user_token);
        END IF;
      END$$;

      CREATE TABLE IF NOT EXISTS rbac_user_roles(
        user_id uuid NOT NULL,
        role_id uuid NOT NULL,
        PRIMARY KEY(user_id, role_id)
      );

      CREATE TABLE IF NOT EXISTS rbac_roles(
        id uuid PRIMARY KEY,
        name text UNIQUE NOT NULL,
        comment text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('rbac_roles_name_idx')) IS NULL THEN
          CREATE INDEX rbac_roles_name_idx on rbac_roles(name);
        END IF;
      END$$;

      CREATE TABLE IF NOT EXISTS rbac_role_entities(
        role_id uuid,
        entity_id uuid,
        entity_type text NOT NULL,
        actions smallint NOT NULL,
        negative boolean NOT NULL,
        comment text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY(role_id, entity_id)
      );

      CREATE TABLE IF NOT EXISTS rbac_role_endpoints(
        role_id uuid,
        workspace text NOT NULL,
        endpoint text NOT NULL,
        actions smallint NOT NULL,
        comment text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        negative boolean NOT NULL,
        PRIMARY KEY(role_id, workspace, endpoint)
      );
    ]],
  },
  {
    name = "2018-04-20-122000_rbac_defaults",
    up = function(_, _, dao)
      local role, ok, err

      -- create read only role
      role, err = dao.rbac_roles:insert({
        id = utils.uuid(),
        name = "read-only",
        comment = "Read access to all endpoints, across all workspaces",
      })
      if err then
        return err
      end

      -- add endpoint permissions to the read only role
      ok, err = dao.rbac_role_endpoints:insert({
        role_id = role.id,
        workspace = "*",
        endpoint = "*",
        actions = rbac.actions_bitfields.read,
      })
      if not ok then
        return err
      end

      -- create admin role
      role, err = dao.rbac_roles:insert({
        id = utils.uuid(),
        name = "admin",
        comment = "Full access to all endpoints, across all workspaces - except RBAC Admin API",
      })
      if err then
        return err
      end

      local action_bits_all = 0x0
      for k, v in pairs(rbac.actions_bitfields) do
        action_bits_all = bor(action_bits_all, rbac.actions_bitfields[k])
      end

      -- add endpoint permissions to the admin role
      ok, err = dao.rbac_role_endpoints:insert({
        role_id = role.id,
        workspace = "*",
        endpoint = "*",
        actions = action_bits_all, -- all actions
      })
      if not ok then
        return err
      end

      -- add negative endpoint permissions to the rbac endpoint
      ok, err = dao.rbac_role_endpoints:insert({
        role_id = role.id,
        workspace = "*",
        endpoint = "/rbac",
        negative = true,
        actions = action_bits_all, -- all actions
      })
      if not ok then
        return err
      end

      -- create super admin role
      role, err = dao.rbac_roles:insert({
        id = utils.uuid(),
        name = "super-admin",
        comment = "Full access to all endpoints, across all workspaces",
      })
      if err then
        return err
      end

      -- add endpoint permissions to the super admin role
      ok, err = dao.rbac_role_endpoints:insert({
        role_id = role.id,
        workspace = "*",
        endpoint = "*",
        actions = action_bits_all, -- all actions
      })
      if not ok then
        return err
      end
    end
  },
  {
    name = "2018-02-01-000000_vitals_stats_v0.31",
    up = [[
      ALTER TABLE vitals_stats_seconds
      ADD COLUMN plat_count int default 0,
      ADD COLUMN plat_total int default 0,
      ADD COLUMN ulat_count int default 0,
      ADD COLUMN ulat_total int default 0;

      ALTER TABLE vitals_stats_minutes
      ADD COLUMN plat_count int default 0,
      ADD COLUMN plat_total int default 0,
      ADD COLUMN ulat_count int default 0,
      ADD COLUMN ulat_total int default 0;
    ]],
    down = [[
      ALTER TABLE vitals_stats_seconds
      DROP COLUMN plat_count,
      DROP COLUMN plat_total,
      DROP COLUMN ulat_count,
      DROP COLUMN ulat_total;

      ALTER TABLE vitals_stats_minutes
      DROP COLUMN plat_count,
      DROP COLUMN plat_total,
      DROP COLUMN ulat_count,
      DROP COLUMN ulat_total;
    ]]
  },
  {
    name = "2018-02-13-621974_portal_files_entity",
    up = [[
      CREATE TABLE IF NOT EXISTS portal_files(
        id uuid PRIMARY KEY,
        auth boolean NOT NULL,
        name text UNIQUE NOT NULL,
        type text NOT NULL,
        contents text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('portal_files_name_idx')) IS NULL THEN
          CREATE INDEX portal_files_name_idx on portal_files(name);
        END IF;
      END$$;
    ]],
    down = [[
      DROP TABLE portal_files;
    ]]
  },
  {
    name = "2018-03-12-000000_vitals_v0.32",
    up = [[
      CREATE TABLE IF NOT EXISTS vitals_code_classes_by_cluster(
        code_class int,
        at timestamp with time zone,
        duration int,
        count int,
        PRIMARY KEY (code_class, duration, at)
      );

      CREATE TABLE IF NOT EXISTS vitals_codes_by_service(
        service_id uuid,
        code int,
        at timestamp with time zone,
        duration int,
        count int,
        PRIMARY KEY (service_id, code, duration, at)
      );

      CREATE TABLE IF NOT EXISTS vitals_codes_by_route(
        service_id uuid,
        route_id uuid,
        code int,
        at timestamp with time zone,
        duration int,
        count int,
        PRIMARY KEY (route_id, code, duration, at)
      );

      CREATE INDEX IF NOT EXISTS vitals_cbr_service_idx
      ON vitals_codes_by_route(service_id);

      CREATE TABLE IF NOT EXISTS vitals_codes_by_consumer_route(
        consumer_id uuid,
        service_id uuid,
        route_id uuid,
        code int,
        at timestamp with time zone,
        duration int,
        count int,
        PRIMARY KEY (consumer_id, route_id, code, duration, at)
      );

      CREATE INDEX IF NOT EXISTS vitals_cbcr_service_idx
      ON vitals_codes_by_consumer_route(consumer_id, service_id);
    ]],

    down = [[
      DROP TABLE vitals_codes_by_consumer_route;
      DROP TABLE vitals_codes_by_route;
      DROP TABLE vitals_codes_by_service;
      DROP TABLE vitals_code_classes_by_cluster;
    ]]
  },
  {
    name = "2018-04-25-000001_portal_initial_files",
    up = function(_, _, dao)
      local utils = require "kong.tools.utils"
      local files = require "kong.portal.migrations.01_initial_files"

      -- Iterate over file list and insert files that do not exist
      for _, file in ipairs(files) do
        dao.portal_files:insert({
          id = utils.uuid(),
          auth = file.auth,
          name = file.name,
          type = file.type,
          contents = file.contents
        })
      end
    end,
  },
  {
    name = "2018-04-10-094800_dev_portal_consumer_types_statuses",
    up = [[
      CREATE TABLE IF NOT EXISTS "consumer_statuses" (
        "id"               int PRIMARY KEY,
        "name" 			       text COLLATE pg_catalog."default" NOT NULL,
        "comment" 		     text COLLATE pg_catalog."default",
        "created_at"       timestamp without time zone DEFAULT timezone('utc'::text, ('now'::text)::timestamp(0) with time zone)
      );

      CREATE TABLE IF NOT EXISTS "consumer_types" (
        "id"               int PRIMARY KEY,
        "name" 			       text COLLATE pg_catalog."default" NOT NULL,
        "comment" 		     text COLLATE pg_catalog."default",
        "created_at"       timestamp without time zone DEFAULT timezone('utc'::text, ('now'::text)::timestamp(0) with time zone)
      );

      CREATE INDEX IF NOT EXISTS consumer_statuses_names_idx
          ON public.consumer_statuses USING btree
          (name COLLATE pg_catalog."default")
          TABLESPACE pg_default;

      CREATE INDEX IF NOT EXISTS consumer_types_name_idx
          ON public.consumer_types USING btree
          (name COLLATE pg_catalog."default")
          TABLESPACE pg_default;
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
        ADD COLUMN "type" int NOT NULL DEFAULT 0 REFERENCES consumer_types (id),
        ADD COLUMN "email" text COLLATE pg_catalog."default",
        ADD COLUMN "status" integer REFERENCES consumer_statuses (id),
        ADD COLUMN "meta" text COLLATE pg_catalog."default";

      ALTER TABLE consumers ADD CONSTRAINT consumers_email_type_key UNIQUE("email", "type");

      CREATE INDEX IF NOT EXISTS consumers_type_idx
          ON consumers USING btree (type)
          TABLESPACE pg_default;

      CREATE INDEX IF NOT EXISTS consumers_status_idx
          ON consumers USING btree (status)
          TABLESPACE pg_default;
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
  }
}
