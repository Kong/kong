return {
  {
    name = "2017-07-13-150200_ratelimiting_lib_counters",
    up = [[
      CREATE TABLE IF NOT EXISTS rl_counters(
        namespace    text,
        window_start timestamp,
        window_size  int,
        key          text,
        count        counter,
        PRIMARY KEY((namespace, window_start, window_size), key)
      );
    ]],
    down = [[
      DROP TABLE rl_counters;
    ]]
  },
  {
    name = "2017-10-03-174200_vitals_stats_seconds",
    up = [[
      CREATE TABLE IF NOT EXISTS vitals_stats_seconds(
        node_id uuid,
        minute timestamp,
        at timestamp,
        l2_hit int,
        l2_miss int,
        plat_min int,
        plat_max int,
        PRIMARY KEY((node_id, minute), at)
      ) WITH CLUSTERING ORDER BY (at DESC);
    ]],
    down = [[
      DROP TABLE vitals_stats_seconds;
    ]]
  },
  {
    name = "2017-10-03-174200_vitals_stats_minutes",
    up = [[
      CREATE TABLE IF NOT EXISTS vitals_stats_minutes(
        node_id uuid,
        hour timestamp,
        at timestamp,
        l2_hit int,
        l2_miss int,
        plat_min int,
        plat_max int,
        PRIMARY KEY((node_id, hour), at)
      ) WITH CLUSTERING ORDER BY (at DESC);
    ]],
    down = [[
      DROP TABLE vitals_stats_minutes;
    ]]
  },
  {
    name = "2017-10-25-114500_vitals_node_meta",
    up = [[
      CREATE TABLE IF NOT EXISTS vitals_node_meta(
        node_id uuid PRIMARY KEY,
        first_report timestamp,
        last_report timestamp,
        hostname text
      );
    ]],
    down = [[
      DROP TABLE vitals_node_meta;
    ]]
  },
  {
    name = "2017-11-06-848722_vitals_consumers",
    up = [[
      CREATE TABLE IF NOT EXISTS vitals_consumers(
        at          timestamp,
        duration    int,
        consumer_id uuid,
        node_id     uuid,
        count       counter,
        PRIMARY KEY((consumer_id, duration), at, node_id)
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
        name text,
        comment text,
        created_at timestamp
      );

      CREATE INDEX IF NOT EXISTS ON workspaces(name);

      CREATE TABLE IF NOT EXISTS workspace_entities(
        workspace_id uuid,
        entity_id text,
        entity_type text,
        unique_field_name text,
        unique_field_value text,
        PRIMARY KEY(workspace_id, entity_id, unique_field_name)
      );
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
        name text,
        user_token text,
        comment text,
        enabled boolean,
        created_at timestamp
      );

      CREATE INDEX IF NOT EXISTS ON rbac_users(name);
      CREATE INDEX IF NOT EXISTS ON rbac_users(user_token);

      CREATE TABLE IF NOT EXISTS rbac_user_roles(
        user_id uuid,
        role_id uuid,
        PRIMARY KEY(user_id, role_id)
      );

      CREATE TABLE IF NOT EXISTS rbac_roles(
        id uuid PRIMARY KEY,
        name text,
        comment text,
        created_at timestamp
      );

      CREATE INDEX IF NOT EXISTS ON rbac_roles(name);

      CREATE TABLE IF NOT EXISTS rbac_role_entities(
        role_id uuid,
        entity_id uuid,
        entity_type text,
        actions int,
        negative boolean,
        comment text,
        created_at timestamp,
        PRIMARY KEY(role_id, entity_id)
      );

      CREATE TABLE IF NOT EXISTS rbac_role_endpoints(
        role_id uuid,
        workspace text,
        endpoint text,
        actions int,
        negative boolean,
        comment text,
        created_at timestamp,
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

}
