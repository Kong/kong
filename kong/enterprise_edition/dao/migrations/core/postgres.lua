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

      CREATE TABLE IF NOT EXISTS role_entities(
        role_id uuid,
        entity_id uuid,
        entity_type text NOT NULL,
        actions smallint NOT NULL,
        negative boolean NOT NULL,
        comment text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY(role_id, entity_id)
      );

      CREATE TABLE IF NOT EXISTS role_endpoints(
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
    down = [[
      DROP TABLE IF EXISTS workspaces;
    ]],
  },
}
