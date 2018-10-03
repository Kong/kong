local rbac_migrations_defaults = require "kong.rbac.migrations.01_defaults"
local rbac_migrations_user_default_role = require "kong.rbac.migrations.03_user_default_role"
local rbac_migrations_default_role_flag = require "kong.rbac.migrations.04_user_default_role_flag"


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
        workspace_name text,
        entity_id text,
        entity_type text,
        unique_field_name text,
        unique_field_value text,
        PRIMARY KEY(workspace_id, entity_id, unique_field_name)
      );

      CREATE INDEX IF NOT EXISTS ON workspace_entities(entity_type);
      CREATE INDEX IF NOT EXISTS ON workspace_entities(unique_field_value);
    ]],
  },
  {
    name = "2018-04-18-110000_old_rbac_cleanup",
    up = [[
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
        entity_id text,
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
    name = "2018-04-20-160001_rbac_rbac_role_defaults",
    up = [[
      ALTER TABLE rbac_roles ADD is_default boolean;
      CREATE INDEX IF NOT EXISTS rbac_role_default_idx on rbac_roles(is_default);
    ]],
  },
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
    name = "2018-04-20-094800_dev_portal_consumer_types_statuses",
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

      CREATE INDEX IF NOT EXISTS consumer_statuses_names_idx ON consumer_statuses(name);
      CREATE INDEX IF NOT EXISTS consumer_types_name_idx ON consumer_types(name);
    ]],

    down = [[
      DROP TABLE consumer_statuses;
      DROP TABLE consumer_types;
      DROP INDEX consumer_statuses_names_idx;
      DROP INDEX consumer_types_name_idx;
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
  {
    name = "2018-05-08-145300_consumer_dev_portal_columns",
    up = [[
      ALTER TABLE consumers ADD type int;
      ALTER TABLE consumers ADD email text;
      ALTER TABLE consumers ADD status int;
      ALTER TABLE consumers ADD meta text;

      CREATE INDEX IF NOT EXISTS consumers_type_idx ON consumers(type);
      CREATE INDEX IF NOT EXISTS consumers_status_idx ON consumers(status);
    ]],

    down = [[
      ALTER TABLE consumers DROP type;
      ALTER TABLE consumers DROP email;
      ALTER TABLE consumers DROP status;
      ALTER TABLE consumers DROP meta;
    ]]
  },
  {
    name = "2018-05-07-171200_credentials_master_table",
    up = [[
      CREATE TABLE IF NOT EXISTS credentials (
        id                 uuid PRIMARY KEY,
        consumer_id        uuid,
        consumer_type      int,
        plugin             text,
        credential_data    text,
        created_at         timestamp
      );


      CREATE INDEX IF NOT EXISTS credentials_consumer_id ON credentials(consumer_id);
      CREATE INDEX IF NOT EXISTS credentials_plugin ON credentials(plugin);
    ]],

    down = [[
      DROP TABLE credentials
    ]]
  },
  {
    name = "2018-05-09-215700_consumers_type_default",
    up = function(_, _, dao)
      local portal = require "kong.portal.dao_helpers"
      local CONSUMERS = require("kong.enterprise_edition.dao.enums").CONSUMERS

      return portal.update_consumers(dao, CONSUMERS.TYPE.PROXY)
    end,
  },
  {
    name = "2018-06-12-111000_consumers_rbac_users_mapping",
    up = [[
      CREATE TABLE IF NOT EXISTS consumers_rbac_users_map(
        consumer_id uuid,
        user_id     uuid,
        created_at  timestamp,
        PRIMARY KEY(consumer_id, user_id)
      );
    ]],
    down = [[
      DROP TABLE consumers_rbac_users_map;
    ]]
  },
  {
    name = "2018-06-12-076222_consumer_type_status_admin",
    up = [[
      INSERT INTO consumer_types(id, name, comment, created_at)
      VALUES (2, 'admin', 'Admin consumer.', dateof(now()));
    ]],
    down = [[
      DELETE FROM consumer_types;
    ]]
  },
  {
    name = "2018-07-18-110000_rbac_role_entities",
    up = [[
      CREATE INDEX IF NOT EXISTS ON rbac_role_entities(entity_type);
    ]],
  },
  {
    name = "2018-08-06-114500_portal_reset_secrets",
    up = [[

      CREATE TABLE IF NOT EXISTS token_statuses(
        id int PRIMARY KEY,
        name text,
        created_at timestamp
      );

      CREATE INDEX IF NOT EXISTS token_statuses_name
      ON token_statuses (name);

      INSERT INTO token_statuses(id, name, created_at)
      VALUES (1, 'pending', dateof(now()));

      INSERT INTO token_statuses(id, name, created_at)
      VALUES (2, 'consumed', dateof(now()));

      INSERT INTO token_statuses(id, name, created_at)
      VALUES (3, 'invalidated', dateof(now()));

      CREATE TABLE IF NOT EXISTS portal_reset_secrets(
        id uuid PRIMARY KEY,
        consumer_id uuid,
        secret text,
        status int,
        client_addr text,
        created_at timestamp,
        updated_at timestamp
      );

      CREATE INDEX IF NOT EXISTS portal_reset_secrets_consumer_id ON portal_reset_secrets (consumer_id);
      CREATE INDEX IF NOT EXISTS portal_reset_secrets_status ON portal_reset_secrets (status);

    ]],
    down = [[
      DROP TABLE portal_reset_secrets;
      DROP TABLE token_statuses;
    ]]
  },
  {
    name = "2018-08-14-000000_vitals_workspaces",
    up = [[
      CREATE TABLE IF NOT EXISTS vitals_code_classes_by_workspace(
        workspace_id uuid,
        at timestamp,
        duration int,
        code_class int,
        count counter,
        PRIMARY KEY((workspace_id, duration), at, code_class)
      );
    ]],
  },
  {
    name = "2018-08-15-100001_rbac_role_defaults",
    up = function(_, _, dao)
      return rbac_migrations_default_role_flag.up(nil, nil, dao)
    end,
  },
  {
    name = "2018-09-05-144800_workspace_meta",
    up = [[
      ALTER TABLE workspaces ADD meta text;
    ]]
  },
  {
    name = "2018-09-24-144900_portal_configs",
    up = [[
      CREATE TABLE IF NOT EXISTS portal_configs(
        id uuid PRIMARY KEY,
        portal_auth text,
        portal_auth_config text,
        portal_auto_approve boolean,
        portal_token_exp int,
        portal_invite_email boolean,
        portal_access_request_email boolean,
        portal_approved_email boolean,
        portal_reset_email boolean,
        portal_reset_success_email boolean,
        portal_emails_from text,
        portal_emails_reply_to text
      );
    ]],
    down = [[
      DROP TABLE portal_configs;
    ]]
  },
  {
    name = "2018-10-03-120000_audit_requests_init",
    up = [[
      CREATE TABLE IF NOT EXISTS audit_requests(
        request_id text,
        request_timestamp timestamp,
        client_ip text,
        path text,
        method text,
        payload text,
        status int,
        rbac_user_id uuid,
        workspace uuid,
        signature text,
        expire timestamp,
        PRIMARY KEY (request_id)
      ) WITH default_time_to_live = 2592000
         AND comment = 'Kong Admin API request audit log';
    ]],
  },
  {
    name = "2018-10-03-120000_audit_objects_init",
    up = [[
      CREATE TABLE IF NOT EXISTS audit_objects(
        id uuid,
        request_id text,
        entity_key uuid,
        dao_name text,
        operation text,
        entity text,
        rbac_user_id uuid,
        signature text,
        PRIMARY KEY (id)
      ) WITH default_time_to_live = 2592000
         AND comment = 'Kong database object audit log';
    ]],
  },
}
