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

      CREATE TABLE IF NOT EXISTS role_entities(
        role_id uuid,
        entity_id uuid,
        entity_type text NOT NULL,
        permissions smallint NOT NULL,
        negative boolean NOT NULL,
        PRIMARY KEY(role_id, entity_id)
      );

      CREATE TABLE IF NOT EXISTS role_endpoints(
        id uuid PRIMARY KEY,
        role_id uuid,
        workspace text NOT NULL,
        endpoint text NOT NULL,
        permissions smallint NOT NULL,
        negative boolean NOT NULL
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('role_endpoints_role_id_idx')) IS NULL THEN
          CREATE INDEX role_endpoints_role_id_idx on role_endpoints(role_id);
        END IF;
      END$$;
    ]],
    down = [[
      DROP TABLE IF EXISTS workspaces;
    ]],
  },
}
