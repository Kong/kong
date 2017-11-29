return {
  {
    name = "2015-01-12-175310_skeleton",
    up = function(db, kong_config)
      local keyspace_name = kong_config.cassandra_keyspace
      local strategy, strategy_properties = kong_config.cassandra_repl_strategy, ""

      -- Format strategy options
      if strategy == "SimpleStrategy" then
        strategy_properties = string.format(", 'replication_factor': %s", kong_config.cassandra_repl_factor)
      elseif strategy == "NetworkTopologyStrategy" then
        local dcs = {}
        for _, dc_conf in ipairs(kong_config.cassandra_data_centers) do
          local dc_name, dc_repl = string.match(dc_conf, "([^:]+):(%d+)")
          if dc_name and dc_repl then
            table.insert(dcs, string.format("'%s': %s", dc_name, dc_repl))
          else
            return "invalid cassandra_data_centers configuration"
          end
        end
        if #dcs > 0 then
          strategy_properties = string.format(", %s", table.concat(dcs, ", "))
        end
      else
        -- Strategy unknown
        return "invalid replication_strategy class"
      end

      -- Format final keyspace creation query
      local keyspace_str = string.format([[
        CREATE KEYSPACE IF NOT EXISTS "%s"
          WITH REPLICATION = {'class': '%s'%s};
      ]], keyspace_name, strategy, strategy_properties)

      local res, err = db:query(keyspace_str, nil, nil, nil, true)
      if not res then
        return err
      end

      local ok, err = db:coordinator_change_keyspace(keyspace_name)
      if not ok then
        return err
      end

      local res, err = db:query [[
        CREATE TABLE IF NOT EXISTS schema_migrations(
          id text PRIMARY KEY,
          migrations list<text>
        );
      ]]
      if not res then
        return err
      end
    end,
    down = [[
      DROP TABLE schema_migrations;
    ]]
  },
  {
    name = "2015-01-12-175310_init_schema",
    up = [[
      CREATE TABLE IF NOT EXISTS consumers(
        id uuid,
        custom_id text,
        username text,
        created_at timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON consumers(custom_id);
      CREATE INDEX IF NOT EXISTS ON consumers(username);

      CREATE TABLE IF NOT EXISTS apis(
        id uuid,
        name text,
        request_host text,
        request_path text,
        strip_request_path boolean,
        upstream_url text,
        preserve_host boolean,
        created_at timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON apis(name);
      CREATE INDEX IF NOT EXISTS ON apis(request_host);
      CREATE INDEX IF NOT EXISTS ON apis(request_path);

      CREATE TABLE IF NOT EXISTS plugins(
        id uuid,
        api_id uuid,
        consumer_id uuid,
        name text,
        config text, -- serialized plugin configuration
        enabled boolean,
        created_at timestamp,
        PRIMARY KEY (id, name)
      );

      CREATE INDEX IF NOT EXISTS ON plugins(name);
      CREATE INDEX IF NOT EXISTS ON plugins(api_id);
      CREATE INDEX IF NOT EXISTS ON plugins(consumer_id);
    ]],
    down = [[
      DROP TABLE consumers;
      DROP TABLE apis;
      DROP TABLE plugins;
    ]]
  },
  {
    name = "2015-11-23-817313_nodes",
    up = [[
      CREATE TABLE IF NOT EXISTS nodes(
        name text,
        cluster_listening_address text,
        created_at timestamp,
        PRIMARY KEY (name)
      ) WITH default_time_to_live = 3600;

      CREATE INDEX IF NOT EXISTS ON nodes(cluster_listening_address);
    ]],
    down = [[
      DROP TABLE nodes;
    ]]
  },
  {
    name = "2016-02-25-160900_remove_null_consumer_id",
    up = function(_, _, dao)
      local rows, err = dao.plugins:find_all {consumer_id = "00000000-0000-0000-0000-000000000000"}
      if err then
        return err
      end

      for _, row in ipairs(rows) do
        row.consumer_id = nil
        local _, err = dao.plugins:update(row, row, {full = true})
        if err then
          return err
        end
      end
    end
  },
  {
    name = "2016-02-29-121813_remove_ttls",
    up = [[
      ALTER TABLE nodes WITH default_time_to_live = 0;
    ]],
    down = [[
      ALTER TABLE nodes WITH default_time_to_live = 3600;
    ]]
  },
  {
    -- This is a 2 step migration; first create the extra column, using a cql
    -- statement and following iterate over the entries to insert default values.

    -- Step 1) create extra column
    name = "2016-09-05-212515_retries_step_1",
    up = [[
      ALTER TABLE apis ADD retries int;
    ]],
    down = [[
      ALTER TABLE apis DROP retries;
    ]]
  },
  {
    -- Step 2) insert default values
    name = "2016-09-05-212515_retries_step_2",
    up = function(_, _, dao)
      local rows, err = dao.apis:find_all() -- fetch all rows
      if err then
        return err
      end

      for _, row in ipairs(rows) do
        if not row.retries then

          local _, err = dao.apis:update({
            retries = 5
          }, {
            id = row.id
          })
          if err then
            return err
          end
        end
      end
    end,
    down = nil,
  },
  {
    name = "2016-09-16-141423_upstreams",
    -- Note on the timestamps;
    -- The Cassandra timestamps are created in Lua code, and hence ALL entities
    -- will now be created in millisecond precision. The existing entries will
    -- remain in second precision, but new ones (for ALL entities!) will be
    -- in millisecond precision.
    -- This differs from the Postgres one where only the new entities (upstreams
    -- and targets) will get millisecond precision.
    up = [[
      CREATE TABLE IF NOT EXISTS upstreams(
        id uuid,
        name text,
        slots int,
        orderlist text,
        created_at timestamp,
        PRIMARY KEY (id)
      );
      CREATE INDEX IF NOT EXISTS ON upstreams(name);
      CREATE TABLE IF NOT EXISTS targets(
        id uuid,
        target text,
        weight int,
        upstream_id uuid,
        created_at timestamp,
        PRIMARY KEY (id)
      );
      CREATE INDEX IF NOT EXISTS ON targets(upstream_id);
    ]],
    down = [[
      DROP TABLE upstreams;
      DROP TABLE targets;
    ]],
  },
  {
    name = "2016-12-14-172100_move_ssl_certs_to_core",
    up = [[
      CREATE TABLE ssl_certificates(
        id uuid PRIMARY KEY,
        cert text,
        key text ,
        created_at timestamp
      );

      CREATE TABLE ssl_servers_names(
        name text,
        ssl_certificate_id uuid,
        created_at timestamp,
        PRIMARY KEY (name, ssl_certificate_id)
      );

      CREATE INDEX IF NOT EXISTS ON ssl_servers_names(ssl_certificate_id);

      ALTER TABLE apis ADD https_only boolean;
      ALTER TABLE apis ADD http_if_terminated boolean;
    ]],
    down = [[
      DROP INDEX ssl_servers_names_ssl_certificate_idx;

      DROP TABLE ssl_certificates;
      DROP TABLE ssl_servers_names;

      ALTER TABLE apis DROP https_only;
      ALTER TABLE apis DROP http_if_terminated;
    ]]
  },
  {
    name = "2016-11-11-151900_new_apis_router_1",
    up = [[
      ALTER TABLE apis ADD hosts text;
      ALTER TABLE apis ADD uris text;
      ALTER TABLE apis ADD methods text;
      ALTER TABLE apis ADD strip_uri boolean;
    ]],
    down = [[
      ALTER TABLE apis DROP headers;
      ALTER TABLE apis DROP uris;
      ALTER TABLE apis DROP methods;
      ALTER TABLE apis DROP strip_uri;
    ]]
  },
  {
    name = "2016-11-11-151900_new_apis_router_2",
    up = function(_, _, dao)
      -- create request_headers and request_uris
      -- with one entry each: the current request_host
      -- and the current request_path
      local rows, err = dao.apis:find_all() -- fetch all rows
      if err then
        return err
      end

      for _, row in ipairs(rows) do
        local hosts
        local uris

        local upstream_url = row.upstream_url
        while string.sub(upstream_url, #upstream_url) == "/" do
          upstream_url = string.sub(upstream_url, 1, #upstream_url - 1)
        end

        if row.request_host then
          hosts = { row.request_host }
        end

        if row.request_path then
          uris = { row.request_path }
        end

        local _, err = dao.apis:update({
          hosts = hosts,
          uris = uris,
          strip_uri = row.strip_request_path,
          upstream_url = upstream_url,
        }, { id = row.id })
        if err then
          return err
        end
      end
    end,
    down = function(_, _, dao)
      -- re insert request_host and request_path from
      -- the first element of request_headers and
      -- request_uris

    end
  },
  {
    name = "2016-11-11-151900_new_apis_router_3",
    up = function(db, kong_config)
      local keyspace_name = kong_config.cassandra_keyspace

      if db.release_version < 3 then
        local rows, err = db:query([[
          SELECT *
          FROM system.schema_columns
          WHERE keyspace_name = ']] .. keyspace_name .. [['
            AND columnfamily_name = 'apis'
            AND column_name IN ('request_host', 'request_path')
        ]])
        if err then
          return err
        end

        for i = 1, #rows do
          if rows[i].index_name then
            local res, err = db:query("DROP INDEX " .. rows[i].index_name)
            if not res then
              return err
            end
          end
        end

      else
        local rows, err = db:query([[
          SELECT *
          FROM system_schema.indexes
          WHERE keyspace_name = ']] .. keyspace_name .. [['
            AND table_name = 'apis'
        ]])
        if err then
          return err
        end

        for i = 1, #rows do
          if rows[i].options and 
             rows[i].options.target == "request_host" or
             rows[i].options.target == "request_path" then

            local res, err = db:query("DROP INDEX " .. rows[i].index_name)
            if not res then
              return err
            end
          end
        end
      end

      local err = db:queries [[
        ALTER TABLE apis DROP request_host;
        ALTER TABLE apis DROP request_path;
        ALTER TABLE apis DROP strip_request_path;
      ]]
      if err then
        return err
      end
    end,
    down = [[
      ALTER TABLE apis ADD request_host text;
      ALTER TABLE apis ADD request_path text;
      ALTER TABLE apis ADD strip_request_path boolean;

      CREATE INDEX IF NOT EXISTS ON apis(request_host);
      CREATE INDEX IF NOT EXISTS ON apis(request_path);
    ]]
  },
  {
    name = "2017-01-24-132600_upstream_timeouts",
    up = [[
      ALTER TABLE apis ADD upstream_connect_timeout int;
      ALTER TABLE apis ADD upstream_send_timeout int;
      ALTER TABLE apis ADD upstream_read_timeout int;
    ]],
    down = [[
      ALTER TABLE apis DROP upstream_connect_timeout;
      ALTER TABLE apis DROP upstream_send_timeout;
      ALTER TABLE apis DROP upstream_read_timeout;
    ]]
  },
  {
    name = "2017-01-24-132600_upstream_timeouts_2",
    up = function(_, _, dao)
      local rows, err = dao.db:query([[
        SELECT * FROM apis;
      ]])
      if err then
        return err
      end

      for _, row in ipairs(rows) do
        if not row.upstream_connect_timeout
          or not row.upstream_read_timeout
          or not row.upstream_send_timeout then

          local _, err = dao.apis:update({
            upstream_connect_timeout = 60000,
            upstream_send_timeout = 60000,
            upstream_read_timeout = 60000,
          }, { id = row.id })
          if err then
            return err
          end
        end
      end
    end,
    down = function(_, _, dao) end
  },
  {
    name = "2017-03-27-132300_anonymous",
    -- this should have been in 0.10, but instead goes into 0.10.1 as a bugfix
    up = function(_, _, dao)
      for _, name in ipairs({
        "basic-auth",
        "hmac-auth",
        "jwt",
        "key-auth",
        "ldap-auth",
        "oauth2",
      }) do
        local rows, err = dao.plugins:find_all( { name = name } )
        if err then
          return err
        end

        for _, row in ipairs(rows) do
          if not row.config.anonymous then
            row.config.anonymous = ""
            local _, err = dao.plugins:update(row, { id = row.id })
            if err then
              return err
            end
          end
        end
      end
    end,
    down = function(_, _, dao) end
  },
  {
    name = "2017-04-04-145100_cluster_events",
    up = [[
      CREATE TABLE IF NOT EXISTS cluster_events(
        channel text,
        at      timestamp,
        node_id uuid,
        data    text,
        id      uuid,
        nbf     timestamp,
        PRIMARY KEY ((channel), at, node_id, id)
      ) WITH default_time_to_live = 86400
         AND comment = 'Kong cluster events broadcasting and polling';
    ]],
  },
  {
    name = "2017-05-19-173100_remove_nodes_table",
    up = [[
      DROP TABLE nodes;
    ]],
  },
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
      local rbac = require "kong.core.rbac"

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
      local rbac  = require "kong.core.rbac"
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
    name = "2017-11-29-167733_rbac_vitals_resources",
    up = function(_, _, dao)
      local rbac = require "kong.core.rbac"
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
}
