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
    name = "2017-07-19-160000_rbac_skeleton",
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

      CREATE TABLE IF NOT EXISTS rbac_role_perms(
        role_id uuid NOT NULL,
        perm_id uuid NOT NULL,
        PRIMARY KEY(role_id, perm_id)
      );

      CREATE TABLE IF NOT EXISTS rbac_perms(
        id uuid PRIMARY KEY,
        name text UNIQUE NOT NULL,
        resources integer NOT NULL,
        actions smallint NOT NULL,
        negative boolean NOT NULL,
        comment text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('rbac_perms_name_idx')) IS NULL THEN
          CREATE INDEX rbac_perms_name_idx on rbac_perms(name);
        END IF;
      END$$;

      CREATE TABLE IF NOT EXISTS rbac_resources(
        id uuid PRIMARY KEY,
        name text UNIQUE NOT NULL,
        bit_pos integer UNIQUE NOT NULL
      );
    ]],
  },
  {
    name = "2017-07-23-100000_rbac_core_resources",
    up = function(_, _, dao)
      local rbac = require "kong.rbac"

      for _, resource in ipairs {
        "default",
        "kong",
        "status",
        "apis",
        "plugins",
        "cache",
        "certificates",
        "consumers",
        "snis",
        "upstreams",
        "targets",
        "rbac",
      } do
          local ok, err = rbac.register_resource(resource, dao)
          if not ok then
            return err
          end
      end
    end,
  },
  {
    name = "2017-07-24-160000_rbac_default_roles",
    up = function(_, _, dao)
      local utils = require "kong.tools.utils"
      local bit   = require "bit"
      local rbac  = require "kong.rbac"
      local bxor  = bit.bxor

      -- default permissions and roles
      -- load our default resources and create our initial permissions
      rbac.load_resource_bitfields(dao)

      -- action int for all
      local action_bits_all = 0x0
      for k, v in pairs(rbac.actions_bitfields) do
        action_bits_all = bxor(action_bits_all, rbac.actions_bitfields[k])
      end

      -- resource int for all
      local resource_bits_all = 0x0
      for i = 1, #rbac.resource_bitfields do
        resource_bits_all = bxor(resource_bits_all, 2 ^ (i - 1))
      end

      local perms = {}
      local roles = {}

      -- read-only permission across all objects
      perms.read_only = dao.rbac_perms:insert({
        id = utils.uuid(),
        name = "read-only",
        resources = resource_bits_all,
        actions = rbac.actions_bitfields["read"],
        negative = false,
        comment = "Read-only permissions across all initial RBAC resources",
      })

      -- read,create,update,delete-resources for all objects
      perms.crud_all = dao.rbac_perms:insert({
        id = utils.uuid(),
        name = "full-access",
        resources = resource_bits_all,
        actions = action_bits_all,
        negative = false,
        comment = "Read/create/update/delete permissions across all objects",
      })

      -- negative rbac permissions (for the default 'admin' role)
      perms.no_rbac = dao.rbac_perms:insert({
        id = utils.uuid(),
        name = "no-rbac",
        resources = rbac.resource_bitfields["rbac"],
        actions = action_bits_all,
        negative = true,
        comment = "Explicit denial of all RBAC resources",
      })

      -- now, create the roles and assign permissions to them

      -- first, a read-only role across everything
      roles.read_only = dao.rbac_roles:insert({
        id = utils.uuid(),
        name = "read-only",
        comment = "Read-only access across all initial RBAC resources",
      })
      -- this role only has the 'read-only' permissions
      dao.rbac_role_perms:insert({
        role_id = roles.read_only.id,
        perm_id = perms.read_only.id,
      })

      -- admin role with CRUD access to all resources except RBAC resource
      roles.admin = dao.rbac_roles:insert({
        id = utils.uuid(),
        name = "admin",
        comment = "CRUD access to most initial resources (no RBAC)",
      })
      -- the 'admin' role has 'full-access' + 'no-rbac' permissions
      dao.rbac_role_perms:insert({
        role_id = roles.admin.id,
        perm_id = perms.crud_all.id,
      })
      dao.rbac_role_perms:insert({
        role_id = roles.admin.id,
        perm_id = perms.no_rbac.id,
      })

      -- finally, a super user role who has access to all initial resources
      roles.super_admin = dao.rbac_roles:insert({
        id = utils.uuid(),
        name = "super-admin",
        comment = "Full CRUD access to all initial resources, including RBAC entities",
      })
      dao.rbac_role_perms:insert({
        role_id = roles.super_admin.id,
        perm_id = perms.crud_all.id,
      })
      -- Setup and Admin user by default if ENV var is set
      if os.getenv("KONG_RBAC_INITIAL_ADMIN_PASS") ~= nil then
        local user, err = dao.rbac_users:insert({
          id = utils.uuid(),
          name = "kong_admin",
          user_token = os.getenv("KONG_RBAC_INITIAL_ADMIN_PASS"),
          enabled = true,
          comment = "Initial RBAC Secure User"
        })
        if err then
          return err
        end
        local _, err = dao.rbac_user_roles:insert({
          user_id = user.id,
          role_id = roles.super_admin.id
        })
        if err then
          return err
        end
      end
    end,
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
    name = "2017-11-29-167733_rbac_vitals_resources",
    up = function(_, _, dao)
      local rbac = require "kong.rbac"
      local bxor = require("bit").bxor

      local resource, err = rbac.register_resource("vitals", dao)

      if not resource then
        return err
      end

      for _, p in ipairs({ "read-only", "full-access" }) do
        local perm, err = dao.rbac_perms:find_all({
          name = p,
        })
        if err then
          return err
        end
        perm = perm[1]
        perm.resources = bxor(perm.resources, 2 ^ (resource.bit_pos - 1))
        local ok, err = dao.rbac_perms:update(perm, { id = perm.id })
        if not ok then
          return err
        end
      end
    end,
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
    name = "2018-03-27-104242_rbac_portal_resource",
    up = function(_, _, dao)
      local rbac = require "kong.rbac"
      local bxor = require("bit").bxor

      local resource, err = rbac.register_resource("portal", dao)

      if not resource then
        return err
      end

      for _, p in ipairs({ "read-only", "full-access" }) do
        local perm, err = dao.rbac_perms:find_all({
          name = p,
        })
        if err then
          return err
        end
        perm = perm[1]
        perm.resources = bxor(perm.resources, 2 ^ (resource.bit_pos - 1))
        local ok, err = dao.rbac_perms:update(perm, { id = perm.id })
        if not ok then
          return err
        end
      end
    end,
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
      ALTER TABLE vitals_codes_by_service
      SET (autovacuum_vacuum_scale_factor = 0.01);

      ALTER TABLE vitals_codes_by_service
      SET (autovacuum_analyze_scale_factor = 0.01);

      CREATE TABLE IF NOT EXISTS vitals_codes_by_route(
        service_id uuid,
        route_id uuid,
        code int,
        at timestamp with time zone,
        duration int,
        count int,
        PRIMARY KEY (route_id, code, duration, at)
      );
      ALTER TABLE vitals_codes_by_route
      SET (autovacuum_vacuum_scale_factor = 0.01);

      ALTER TABLE vitals_codes_by_route
      SET (autovacuum_analyze_scale_factor = 0.01);

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
      ALTER TABLE vitals_codes_by_consumer_route
      SET (autovacuum_vacuum_scale_factor = 0.01);

      ALTER TABLE vitals_codes_by_consumer_route
      SET (autovacuum_analyze_scale_factor = 0.01);
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
      CREATE TABLE IF NOT EXISTS consumer_statuses (
        id               int PRIMARY KEY,
        name 			       text COLLATE pg_catalog."default" NOT NULL,
        comment 		     text COLLATE pg_catalog."default",
        created_at       timestamp without time zone DEFAULT timezone('utc'::text, ('now'::text)::timestamp(0) with time zone)
      );

      CREATE TABLE IF NOT EXISTS consumer_types (
        id               int PRIMARY KEY,
        name 			       text COLLATE pg_catalog."default" NOT NULL,
        comment 		     text COLLATE pg_catalog."default",
        created_at       timestamp without time zone DEFAULT timezone('utc'::text, ('now'::text)::timestamp(0) with time zone)
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
        ADD COLUMN type int NOT NULL DEFAULT 0 REFERENCES consumer_types (id),
        ADD COLUMN email text COLLATE pg_catalog."default",
        ADD COLUMN status integer REFERENCES consumer_statuses (id),
        ADD COLUMN meta text COLLATE pg_catalog."default";

      ALTER TABLE consumers ADD CONSTRAINT consumers_email_type_key UNIQUE(email, type);

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
        ON credentials USING btree (consumer_id)
        TABLESPACE pg_default;

      CREATE INDEX IF NOT EXISTS credentials_consumer_id_plugin
        ON credentials USING btree (consumer_id, plugin)
        TABLESPACE pg_default;
    ]],

    down = [[
      DROP TABLE credentials
    ]]
  },
  {
    name = "2018-05-15-100000_rbac_routes_services",
    up = function(_, _, dao)
      local rbac = require "kong.rbac"
      local bxor = require("bit").bxor

      for _, resource in ipairs {
        "routes",
        "services",
      } do
        local resource, err = rbac.register_resource(resource, dao)
        if not resource then
          return err
        end

        for _, p in ipairs({ "read-only", "full-access" }) do
          local perm, err = dao.rbac_perms:find_all({
            name = p,
          })
          if err then
            return err
          end
          perm = perm[1]
          perm.resources = bxor(perm.resources, 2 ^ (resource.bit_pos - 1))
          local ok, err = dao.rbac_perms:update(perm, { id = perm.id })
          if not ok then
            return err
          end
        end
      end
    end
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
}
