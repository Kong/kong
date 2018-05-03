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
    name = "2018-01-16-160000_vitals_stats_v0.31",
    up = [[
      DROP TABLE IF EXISTS vitals_stats_seconds;
      DROP TABLE IF EXISTS vitals_stats_minutes;

      CREATE TABLE vitals_stats_seconds(
        node_id uuid,
        at timestamp,
        l2_hit int,
        l2_miss int,
        plat_min int,
        plat_max int,
        ulat_min int,
        ulat_max int,
        requests int,
        plat_count int,
        plat_total int,
        ulat_count int,
        ulat_total int,
        PRIMARY KEY(node_id, at)
      ) WITH CLUSTERING ORDER BY (at DESC);

      CREATE TABLE vitals_stats_minutes(
        node_id uuid,
        at timestamp,
        l2_hit int,
        l2_miss int,
        plat_min int,
        plat_max int,
        ulat_min int,
        ulat_max int,
        requests int,
        plat_count int,
        plat_total int,
        ulat_count int,
        ulat_total int,
        PRIMARY KEY(node_id, at)
      ) WITH CLUSTERING ORDER BY (at DESC);
    ]],

    down = [[
      DROP TABLE vitals_stats_seconds;
      DROP TABLE vitals_stats_minutes;
    ]]
  },
  {
    name = "2018-02-13-621974_portal_files_entity",
    up = [[
      CREATE TABLE IF NOT EXISTS portal_files(
        id uuid,
        auth boolean,
        name text,
        type text,
        contents text,
        created_at timestamp,
        PRIMARY KEY (id, name)
      );

      CREATE INDEX IF NOT EXISTS ON portal_files(name);
      CREATE INDEX IF NOT EXISTS ON portal_files(type);
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
        at timestamp,
        duration int,
        code_class int,
        count counter,
        PRIMARY KEY((code_class, duration), at)
      );

      CREATE TABLE IF NOT EXISTS vitals_codes_by_service(
        service_id uuid,
        code int,
        at timestamp,
        duration int,
        count counter,
        PRIMARY KEY ((service_id, duration), at, code)
      );

      CREATE TABLE IF NOT EXISTS vitals_codes_by_route(
        route_id uuid,
        code int,
        at timestamp,
        duration int,
        count counter,
        PRIMARY KEY ((route_id, duration), at, code)
      );

      CREATE TABLE IF NOT EXISTS vitals_codes_by_consumer_route(
        consumer_id uuid,
        route_id uuid,
        service_id uuid,
        code int,
        at timestamp,
        duration int,
        count counter,
        PRIMARY KEY ((consumer_id, duration), at, code, route_id, service_id)
      );
    ]],

    down = [[
      DROP TABLE vitals_codes_by_service;
      DROP TABLE vitals_codes_by_route;
      DROP TABLE vitals_codes_by_consumer_route;
      DROP TABLE vitals_code_classes_by_cluster;
    ]]
  },
  {
    name = "2018-04-20-160400_dev_portal_consumer_types",
    up = [[
      CREATE TABLE IF NOT EXISTS consumer_statuses (
        id               int PRIMARY KEY,
        name 			       text,
        comment 		     text,
        created_at       timestamp
      );

      CREATE TABLE IF NOT EXISTS consumer_types (
        id               int PRIMARY KEY,
        name 			       text,
        comment 		     text,
        created_at       timestamp
      );

      ALTER TABLE consumers ADD type int;
      ALTER TABLE consumers ADD email text;
      ALTER TABLE consumers ADD status int;
      ALTER TABLE consumers ADD meta text;

      CREATE INDEX IF NOT EXISTS consumers_type_idx ON consumers(type);
      CREATE INDEX IF NOT EXISTS consumers_status_idx ON consumers(status);

      CREATE INDEX IF NOT EXISTS consumer_statuses_names_idx ON consumer_statuses(name);
      CREATE INDEX IF NOT EXISTS consumer_types_name_idx ON consumer_types(name);
    ]],

    down = [[
      DROP TABLE consumer_statuses;
      DROP TABLE consumer_types;
      DROP INDEX consumer_statuses_names_idx;
      DROP INDEX consumer_types_name_idx;
      ALTER TABLE consumers DROP type;
      ALTER TABLE consumers DROP email;
      ALTER TABLE consumers DROP status;
      ALTER TABLE consumers DROP meta;
    ]]
  },
  {
    name = "2018-04-20-160400_consumer_type_status_defaults",
    up = function(_, _, dao)
      local helper = require('kong.portal.dao_helpers')

      return helper.register_resources(dao)
    end,

    down = [[
      DELETE FROM consumer_statuses;
      DELETE FROM consumer_types;
    ]]
  },
}
