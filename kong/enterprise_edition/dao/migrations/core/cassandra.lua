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
    name = "2017-07-19-160000_rbac_skeleton",
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

      CREATE TABLE IF NOT EXISTS rbac_role_perms(
        role_id uuid,
        perm_id uuid,
        PRIMARY KEY(role_id, perm_id)
      );

      CREATE TABLE IF NOT EXISTS rbac_perms(
        id uuid PRIMARY KEY,
        name text,
        resources int,
        actions int,
        negative boolean,
        comment text,
        created_at timestamp
      );

      CREATE INDEX IF NOT EXISTS ON rbac_perms(name);

      CREATE TABLE IF NOT EXISTS rbac_resources(
        id uuid PRIMARY KEY,
        name text,
        bit_pos int
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
    end,
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
  }
}
