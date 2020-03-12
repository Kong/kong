local utils = require "kong.tools.utils"
local crypto = require "kong.plugins.basic-auth.crypto"

local audit_ttl = kong.configuration.audit_log_record_ttl
local fmt = string.format

-- purposedly hardcoded. This migration is fixed in time. Even if the name of
-- the default workspace (or the delimiter) changes over time, we will do that
-- on a migration, not on the base (until squash)
local DEFAULT_WORKSPACE = "default"
local WORKSPACE_DELIMITER = ":"
local password = os.getenv("KONG_PASSWORD")


-- common lua land functionality
local base_seed = {
  uuid = function(self)
    return utils.uuid()
  end,
  ts = function(self)
      return math.floor(ngx.now()) * 1000
  end,
  wsd = function(self, ws, name)
    return ws.name .. ":" .. name
  end,
  add_default_rbac_role_endpoints = function(self, role_id_map)
    return table.concat({
      self:add_rbac_role_endpoint(role_id_map["read-only"], "*", "*", 1, false),
      self:add_rbac_role_endpoint(role_id_map["admin"], "*", "*", 15, false),
      self:add_rbac_role_endpoint(role_id_map["admin"], "*", "/rbac/*", 15, true),
      self:add_rbac_role_endpoint(role_id_map["admin"], "*", "/rbac/*/*", 15, true),
      self:add_rbac_role_endpoint(role_id_map["admin"], "*", "/rbac/*/*/*", 15, true),
      self:add_rbac_role_endpoint(role_id_map["admin"], "*", "/rbac/*/*/*/*", 15, true),
      self:add_rbac_role_endpoint(role_id_map["admin"], "*", "/rbac/*/*/*/*/*", 15, true),
      self:add_rbac_role_endpoint(role_id_map["super-admin"], "*", "*", 15, false),
    }, "\n")
  end,
  add_default_rbac_roles = function(self, ws)
    local ro, ro_id = self:add_rbac_role(ws, "read-only", "Read access to all endpoints, across all workspaces", false)
    local ad, ad_id = self:add_rbac_role(ws, "admin", "Full access to all endpoints, across all workspaces—except RBAC Admin API", false)
    local sa, sa_id = self:add_rbac_role(ws, "super-admin", "Full access to all endpoints, across all workspaces", false)

    return table.concat({
      "-- read only role", ro,
      "-- admin role", ad,
      "-- super admin role", sa
    }, "\n"), { ["read-only"] = ro_id, ["admin"] = ad_id, ["super-admin"] = sa_id }
  end,
  seed = function(self, password)
    local ws_q, ws_id = self:add_workspace(DEFAULT_WORKSPACE)
    local ws = {
      id = ws_id,
      name = "default",
    }
    local roles_q, roles_ids = self:add_default_rbac_roles(ws)
    local query = {
      "-- seed kong enterprise data", "",
      "-- add default workspace",
      ws_q,
      "",
      "-- add default RBAC roles",
      roles_q,
      "-- add default rbac role endpoints",
      self:add_default_rbac_role_endpoints(roles_ids),
      -- the end, if no password is set
    }

    if password then
      table.insert(query, "")
      table.insert(query, "-- Add rbac user named kong_admin")
      local add_rbac_user_q, rbac_user_id = self:add_rbac_user("kong_admin", password, "Initial RBAC Secure User", ws)
      table.insert(query, add_rbac_user_q)

      table.insert(query, "-- create default role for the user")
      local admin_role_q, admin_role_id = self:add_rbac_role(ws, "kong_admin", "Default user role generated for kong_admin", true)
      table.insert(query, admin_role_q)

      table.insert(query, "-- Add super-admin role and his own role to kong_admin")
      table.insert(query, self:add_rbac_user_role(rbac_user_id, roles_ids["super-admin"]))
      table.insert(query, self:add_rbac_user_role(rbac_user_id, admin_role_id))
      table.insert(query, "")

      table.insert(query, "-- Add kong_admin")
      table.insert(query,  self:add_admin("kong_admin", password, rbac_user_id, ws))
    end

    return table.concat(query, "\n")
  end,
}

local postgres  = {
  super = base_seed,
  seed = function(self, password)
    local query = {
      "-- reentrant, do not seed if it looks seeded",
      [[ DO $$
         DECLARE tmp record;
         BEGIN
         SELECT * into tmp FROM workspaces LIMIT 1;
         IF NOT FOUND THEN
      ]],
      self.super.seed(self, password),
      "END IF;",
      "END $$",
      "-- end",
    }
    return table.concat(query, "\n")
  end,
  add_workspace = function(self, name)
    local ws_uuid = self:uuid()
    return fmt("INSERT INTO workspaces(id, name) VALUES ('%s', '%s') ON CONFLICT DO NOTHING;", ws_uuid, name), ws_uuid
  end,

  add_to_ws = function(self, ws, entity_id, entity, field, value)
    -- XXX Properly sql escape this
    local value = value and "'" .. value .. "'" or "NULL"
    return fmt("INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES ('%s', '%s', '%s', '%s', '%s', %s);", ws.id, ws.name, entity_id, entity, field, value)
  end,

  add_rbac_user = function(self, name, password, comment, ws)
    local uuid = self:uuid()

    return table.concat({
      fmt("INSERT INTO rbac_users(id, name, user_token, enabled, comment) VALUES('%s', '%s', '%s', true, '%s');", uuid, self:wsd(ws, name), password, comment),
      self:add_to_ws(ws, uuid, "rbac_users", "id", uuid),
      self:add_to_ws(ws, uuid, "rbac_users", "name", name),
      self:add_to_ws(ws, uuid, "rbac_users", "user_token", password),
    }, "\n"), uuid
  end,

  add_rbac_role = function(self, ws, name, desc, is_default)
    local role_id = self:uuid()
    local name = self:wsd(ws, name)
    local query = {
      fmt("INSERT INTO rbac_roles(id, name, comment, is_default) VALUES ('%s', '%s', '%s', %s);", role_id, name, desc, tostring(is_default)),
      self:add_to_ws(ws, role_id, "rbac_roles", "id", role_id),
      self:add_to_ws(ws, role_id, "rbac_roles", "name", name),
    }

    return table.concat(query, "\n"), role_id
  end,

  add_rbac_user_role = function(self, rbac_user_id, role_id)
    return fmt("INSERT INTO rbac_user_roles(user_id, role_id) VALUES ('%s', '%s');", rbac_user_id, role_id)
  end,

  add_rbac_role_endpoint = function(self, role_id, ws, endpoint, actions, negative)

    -- assumedly, only do that if not found
    return fmt("INSERT INTO rbac_role_endpoints(role_id, workspace, endpoint, actions, negative) VALUES ('%s', '%s', '%s', %d, %s);", role_id, ws, endpoint, actions, tostring(negative))
  end,

  add_admin = function(self, name, password, rbac_user_id, ws)
    local admin_id = utils.uuid()
    local consumer_id = utils.uuid()
    local ba_id = utils.uuid()

    local hash_password = crypto.hash(consumer_id, password)

    return table.concat({
      "-- add a consumer to associate to an admin, with type admin (2)",
      fmt("INSERT INTO consumers(id, username, type) VALUES ('%s', '%s', %d);", consumer_id, self:wsd(ws, name), 2),
      self:add_to_ws(ws, consumer_id, "consumers", "id", consumer_id),
      self:add_to_ws(ws, consumer_id, "consumers", "username", name),
      self:add_to_ws(ws, consumer_id, "consumers", "custom_id", nil),
      "",
      fmt("INSERT INTO admins(id, username, consumer_id, rbac_user_id, rbac_token_enabled) VALUES ('%s', '%s', '%s', '%s', true);", admin_id, name, consumer_id, rbac_user_id),
      self:add_to_ws(ws, admin_id, "admins", "id", admin_id),
      self:add_to_ws(ws, admin_id, "admins", "username", name),
      self:add_to_ws(ws, admin_id, "admins", "custom_id", nil),
      self:add_to_ws(ws, admin_id, "admins", "email", nil),
      "",
      "-- add basic auth credentials asociated to this admin",
      fmt("INSERT INTO basicauth_credentials(id, consumer_id, username, password) VALUES ('%s', '%s', '%s', '%s');", ba_id, consumer_id, self:wsd(ws, name), hash_password),
      self:add_to_ws(ws, ba_id, "basicauth_credentials", "id", ba_id),
      self:add_to_ws(ws, ba_id, "basicauth_credentials", "username", name),
    }, "\n")
  end,
  is_seeded = function(self, connector)
    local res = connector:query("SELECT COUNT(*) AS ct FROM workspaces;")
    return res and res[1].ct and res[1].ct > 0 or false
  end,
}

local cassandra = {
  super = base_seed,
  add_workspace = function(self, name)
    local ws_uuid = self:uuid()

    return fmt("INSERT INTO workspaces(id, name, config, meta, created_at) VALUES (%s, '%s', '{\"portal\":false}', '{}', '%s');", ws_uuid, name, self:ts()), ws_uuid
  end,

  add_to_ws = function(self, ws, entity_id, entity, field, value)
    local value = value and "'" .. value .. "'" or "null"

    return fmt("INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES (%s, '%s', '%s', '%s', '%s', %s);", ws.id, ws.name, entity_id, entity, field, value)
  end,

  add_rbac_user = function(self, name, password, comment, ws)
    local uuid = utils.uuid()

    return table.concat({
      fmt("INSERT INTO rbac_users(id, name, user_token, enabled, comment, created_at) VALUES(%s, '%s', '%s', true, '%s', '%s');", uuid, self:wsd(ws, name), password, comment, self:ts()),
      self:add_to_ws(ws, uuid, "rbac_users", "id", uuid),
      self:add_to_ws(ws, uuid, "rbac_users", "name", name),
      self:add_to_ws(ws, uuid, "rbac_users", "user_token", password),
    }, "\n"), uuid
  end,

  add_rbac_role = function(self, ws, name, desc, is_default)
    local role_id = self:uuid()
    local name = ws.name .. WORKSPACE_DELIMITER .. name
    local query = {
      fmt("INSERT INTO rbac_roles(id, name, comment, is_default, created_at) VALUES (%s, '%s', '%s', %s, '%s');", role_id, name, desc, tostring(is_default), self:ts()),
      self:add_to_ws(ws, role_id, "rbac_roles", "id", role_id),
      self:add_to_ws(ws, role_id, "rbac_roles", "name", name),
    }

    return table.concat(query, "\n"), role_id
  end,

  add_rbac_user_role = function(self, rbac_user_id, role_id)
    return fmt("INSERT INTO rbac_user_roles(user_id, role_id) VALUES (%s, %s);", rbac_user_id, role_id)
  end,
  add_rbac_role_endpoint = function(self, role_id, ws, endpoint, actions, negative)
    -- assumedly, only do that if not found
    return fmt("INSERT INTO rbac_role_endpoints(role_id, workspace, endpoint, actions, negative, created_at) VALUES (%s, '%s', '%s', %d, %s, '%s');", role_id, ws, endpoint, actions, tostring(negative), self:ts())
  end,
  add_entity = function(self, entity_type, fields, values)
    return fmt("INSERT INTO %s(%s) VALUES (%s);", entity_type, table.concat(fields, ","), table.concat(values, ","))
  end,
  add_admin = function(self, name, password, rbac_user_id, ws)
    local admin_id = utils.uuid()
    local consumer_id = utils.uuid()
    local ba_id = utils.uuid()

    local hash_password = crypto.hash(consumer_id, password)

    return table.concat({
      "-- add a consumer to associate to an admin, with type admin (2)",
      fmt("INSERT INTO consumers(id, username, type, created_at) VALUES (%s, '%s', %d, '%s');", consumer_id, self:wsd(ws, name), 2, self:ts()),
      self:add_to_ws(ws, consumer_id, "consumers", "id", consumer_id),
      self:add_to_ws(ws, consumer_id, "consumers", "username", name),
      self:add_to_ws(ws, consumer_id, "consumers", "custom_id", nil),
      "",
      fmt("INSERT INTO admins(id, username, consumer_id, rbac_user_id, rbac_token_enabled, created_at) VALUES (%s, '%s', %s, %s, true, '%s');", admin_id, name, consumer_id, rbac_user_id, self:ts()),
      self:add_to_ws(ws, admin_id, "admins", "id", admin_id),
      self:add_to_ws(ws, admin_id, "admins", "username", name),
      self:add_to_ws(ws, admin_id, "admins", "custom_id", nil),
      self:add_to_ws(ws, admin_id, "admins", "email", nil),
      "",
      "-- add basic auth credentials asociated to this admin",
      fmt("INSERT INTO basicauth_credentials(id, consumer_id, username, password, created_at) VALUES (%s, %s, '%s', '%s', '%s');", ba_id, consumer_id, self:wsd(ws, name), hash_password, self:ts()),
      self:add_to_ws(ws, ba_id, "basicauth_credentials", "id", ba_id),
      self:add_to_ws(ws, ba_id, "basicauth_credentials", "username", name),
    }, "\n")
  end,
  is_seeded = function(self, connector)
    local res = connector:query("SELECT COUNT(*) AS ct FROM workspaces;")
    return res and res[1].ct and res[1].ct > 0 or false
  end,
}


local seed_strategies = {
  postgres = setmetatable(postgres, { __index = base_seed }),
  cassandra = setmetatable(cassandra, { __index = base_seed }),
}


local seed = function(strategy, password)
  return seed_strategies[strategy]:seed(password)
end


return {
  postgres = {
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



      CREATE TABLE IF NOT EXISTS vitals_stats_hours(
          at integer,
          l2_hit integer default 0,
          l2_miss integer default 0,
          plat_min integer,
          plat_max integer,
          PRIMARY KEY (at)
      );

      CREATE TABLE IF NOT EXISTS vitals_stats_seconds(
          node_id uuid,
          at integer,
          l2_hit integer default 0,
          l2_miss integer default 0,
          plat_min integer,
          plat_max integer,
          ulat_min integer,
          ulat_max integer,
          requests integer default 0,
          plat_count int default 0,
          plat_total int default 0,
          ulat_count int default 0,
          ulat_total int default 0,
          PRIMARY KEY (node_id, at)
      );



      CREATE TABLE IF NOT EXISTS vitals_stats_minutes
      (LIKE vitals_stats_seconds INCLUDING defaults INCLUDING constraints INCLUDING indexes);



      CREATE TABLE IF NOT EXISTS vitals_node_meta(
        node_id uuid PRIMARY KEY,
        first_report timestamp without time zone,
        last_report timestamp without time zone,
        hostname text
      );



      CREATE TABLE IF NOT EXISTS vitals_code_classes_by_cluster(
        code_class int,
        at timestamp with time zone,
        duration int,
        count int,
        PRIMARY KEY (code_class, duration, at)
      );



      CREATE TABLE IF NOT EXISTS vitals_codes_by_route(
        service_id uuid,
        route_id uuid,
        code int,
        at timestamp with time zone,
        duration int,
        count int,
        PRIMARY KEY (route_id, code, duration, at)
      ) WITH (autovacuum_vacuum_scale_factor='0.01', autovacuum_analyze_scale_factor='0.01');

      CREATE INDEX IF NOT EXISTS vcbr_svc_ts_idx
      ON vitals_codes_by_route(service_id, duration, at);



      CREATE TABLE IF NOT EXISTS vitals_codes_by_consumer_route(
        consumer_id uuid,
        service_id uuid,
        route_id uuid,
        code int,
        at timestamp with time zone,
        duration int,
        count int,
        PRIMARY KEY (consumer_id, route_id, code, duration, at)
      ) WITH (autovacuum_vacuum_scale_factor='0.01', autovacuum_analyze_scale_factor='0.01');



      CREATE TABLE IF NOT EXISTS vitals_code_classes_by_workspace(
        workspace_id uuid,
        code_class int,
        at timestamp with time zone,
        duration int,
        count int,
        PRIMARY KEY (workspace_id, code_class, duration, at)
      );



      CREATE TABLE IF NOT EXISTS vitals_locks(
        key text,
        expiry timestamp with time zone,
        PRIMARY KEY(key)
      );
      INSERT INTO vitals_locks(key, expiry)
      VALUES ('delete_status_codes', NULL) ON CONFLICT DO NOTHING;



      CREATE TABLE IF NOT EXISTS workspaces (
        id  UUID                  PRIMARY KEY,
        name                      TEXT                      UNIQUE,
        comment                   TEXT,
        created_at                TIMESTAMP WITH TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        meta                      JSON                      DEFAULT '{}'::json,
        config                    JSON                      DEFAULT '{"portal":false}'::json
      );


      CREATE TABLE IF NOT EXISTS workspace_entities(
        workspace_id uuid,
        workspace_name text,
        entity_id text,
        entity_type text,
        unique_field_name text,
        unique_field_value text,
        PRIMARY KEY(workspace_id, entity_id, unique_field_name)
      );

      CREATE INDEX IF NOT EXISTS workspace_entities_idx_entity_id ON workspace_entities(entity_id);

      DO $$
      BEGIN
        IF (SELECT to_regclass('workspace_entities_composite_idx')) IS NULL THEN
          CREATE INDEX workspace_entities_composite_idx on workspace_entities(workspace_id, entity_type, unique_field_name);
        END IF;
      END$$;


      CREATE TABLE IF NOT EXISTS workspace_entity_counters(
        workspace_id uuid REFERENCES workspaces (id) ON DELETE CASCADE,
        entity_type text,
        count int,
        PRIMARY KEY(workspace_id, entity_type)
      );


      CREATE TABLE IF NOT EXISTS rbac_users(
        id uuid PRIMARY KEY,
        name text UNIQUE NOT NULL,
        user_token text UNIQUE NOT NULL,
        user_token_ident text,
        comment text,
        enabled boolean NOT NULL,
        created_at timestamp WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC')
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('rbac_users_name_idx')) IS NULL THEN
          CREATE INDEX rbac_users_name_idx on rbac_users(name);
        END IF;
        IF (SELECT to_regclass('rbac_users_token_idx')) IS NULL THEN
          CREATE INDEX rbac_users_token_idx on rbac_users(user_token);
        END IF;
        IF (SELECT to_regclass('rbac_token_ident_idx')) IS NULL THEN
          CREATE INDEX rbac_token_ident_idx on rbac_users(user_token_ident);
        END IF;
      END$$;

      CREATE TABLE IF NOT EXISTS rbac_roles(
        id uuid PRIMARY KEY,
        name text UNIQUE NOT NULL,
        comment text,
        created_at timestamp WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        is_default boolean default false
      );


      CREATE TABLE IF NOT EXISTS rbac_user_roles(
        user_id uuid NOT NULL REFERENCES rbac_users(id) ON DELETE CASCADE,
        role_id uuid NOT NULL REFERENCES rbac_roles(id) ON DELETE CASCADE,
        PRIMARY KEY(user_id, role_id)
      );

      CREATE INDEX IF NOT EXISTS rbac_roles_name_idx on rbac_roles(name);
      CREATE INDEX IF NOT EXISTS rbac_role_default_idx on rbac_roles(is_default);

      CREATE TABLE IF NOT EXISTS rbac_role_entities(
        role_id uuid REFERENCES rbac_roles(id) ON DELETE CASCADE,
        entity_id text,
        entity_type text NOT NULL,
        actions smallint NOT NULL,
        negative boolean NOT NULL,
        comment text,
        created_at                TIMESTAMP WITH TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        PRIMARY KEY(role_id, entity_id)
      );

      CREATE INDEX IF NOT EXISTS rbac_role_entities_role_idx on rbac_role_entities(role_id);

      CREATE TABLE IF NOT EXISTS rbac_role_endpoints(
        role_id uuid,
        workspace text NOT NULL,
        endpoint text NOT NULL,
        actions smallint NOT NULL,
        comment text,
        created_at                TIMESTAMP WITH TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        negative boolean NOT NULL,
        PRIMARY KEY(role_id, workspace, endpoint),
        FOREIGN KEY (role_id) REFERENCES rbac_roles(id) ON DELETE CASCADE
      );

      CREATE INDEX IF NOT EXISTS rbac_role_endpoints_role_idx on rbac_role_endpoints(role_id);

      CREATE TABLE IF NOT EXISTS files(
        id uuid PRIMARY KEY,
        path text UNIQUE NOT NULL,
        checksum text,
        contents text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );

      CREATE INDEX IF NOT EXISTS files_path_idx on files(path);

      -- XXX
      -- this table comes from a migration from the future. At this step is
      -- going to always be empty, but there's already code supporting this
      -- table so I guess we need it here?
      CREATE TABLE IF NOT EXISTS legacy_files(
        id uuid PRIMARY KEY,
        auth boolean NOT NULL,
        name text UNIQUE NOT NULL,
        type text NOT NULL,
        contents text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );

      CREATE INDEX IF NOT EXISTS legacy_files_name_idx on legacy_files(name);

      DO $$
      BEGIN
        IF not EXISTS (SELECT column_name
               FROM information_schema.columns
               WHERE table_schema=current_schema() and table_name='consumers' and column_name='type') THEN
          ALTER TABLE consumers
            ADD COLUMN type int NOT NULL DEFAULT 0;
         END IF;
      END$$;

      CREATE INDEX IF NOT EXISTS consumers_type_idx
        ON consumers (type);

      CREATE TABLE IF NOT EXISTS credentials (
        id                uuid PRIMARY KEY,
        consumer_id       uuid REFERENCES consumers (id) ON DELETE CASCADE,
        consumer_type     integer,
        plugin            text NOT NULL,
        credential_data   json,
        created_at        timestamp without time zone DEFAULT timezone('utc'::text, ('now'::text)::timestamp(0) with time zone)
      );

      CREATE INDEX IF NOT EXISTS credentials_consumer_type
        ON credentials (consumer_id);

      CREATE INDEX IF NOT EXISTS credentials_consumer_id_plugin
        ON credentials (consumer_id, plugin);



      CREATE TABLE IF NOT EXISTS consumer_reset_secrets(
        id uuid PRIMARY KEY,
        consumer_id uuid REFERENCES consumers (id) ON DELETE CASCADE,
        secret text,
        status integer,
        client_addr text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        updated_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );

      CREATE INDEX IF NOT EXISTS consumer_reset_secrets_consumer_id_idx
        ON consumer_reset_secrets(consumer_id);

      CREATE TABLE IF NOT EXISTS admins (
        id          uuid,
        created_at  TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        updated_at  TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        consumer_id  uuid references consumers (id),
        rbac_user_id  uuid references rbac_users (id),
        rbac_token_enabled BOOLEAN NOT NULL,
        email text,
        status int,
        username text unique,
        custom_id text unique,
        PRIMARY KEY(id)
      );

      CREATE TABLE IF NOT EXISTS developers (
        id          uuid,
        created_at  timestamp,
        updated_at  timestamp,
        email text  unique,
        status int,
        meta text,
        custom_id text unique,
        consumer_id  uuid references consumers (id) on delete cascade,
        rbac_user_id uuid,
        PRIMARY KEY(id)
      );

      CREATE INDEX IF NOT EXISTS developers_rbac_user_id_idx ON developers(rbac_user_id);

      CREATE TABLE IF NOT EXISTS audit_objects(
        id uuid PRIMARY KEY,
        request_id char(32),
        entity_key uuid,
        dao_name text NOT NULL,
        operation char(6) NOT NULL,
        entity text,
        rbac_user_id uuid,
        signature text,
        ttl timestamp with time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc' + interval ']] .. audit_ttl .. [[')
      );

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
        ttl timestamp with time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc' + interval ']] .. audit_ttl .. [[')
      );

      -- Groups Entity
      CREATE TABLE IF NOT EXISTS groups (
        id          uuid,
        created_at  TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        name text unique,
        comment text,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS groups_name_idx ON groups(name);

      -- Group and RBAC_Role Mapping
      CREATE TABLE IF NOT EXISTS group_rbac_roles(
        created_at  TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        group_id uuid REFERENCES groups (id) ON DELETE CASCADE,
        rbac_role_id uuid REFERENCES rbac_roles (id) ON DELETE CASCADE,
        workspace_id uuid REFERENCES workspaces (id) ON DELETE CASCADE,
        PRIMARY KEY (group_id, rbac_role_id)
      );

      -- License data
      CREATE TABLE IF NOT EXISTS license_data (
        node_id         uuid,
        req_cnt         bigint,
        PRIMARY KEY (node_id)
      );

      CREATE INDEX IF NOT EXISTS license_data_key_idx ON license_data(node_id);

      -- Login Attempts
      CREATE TABLE IF NOT EXISTS login_attempts (
        consumer_id uuid REFERENCES consumers (id) ON DELETE CASCADE,
        attempts json DEFAULT '{}'::json,
        ttl         TIMESTAMP WITH TIME ZONE,
        created_at  TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        PRIMARY KEY (consumer_id)
      );

      CREATE TABLE IF NOT EXISTS keyring_meta (
        id text PRIMARY KEY,
        state text not null,
        created_at timestamp with time zone not null
      );

    ]] .. seed("postgres", password) .. [[
      -- The end
    ]],
  },
  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS rl_counters(
        namespace    text,
        window_start timestamp,
        window_size  int,
        key          text,
        count        counter,
        PRIMARY KEY((namespace, window_start, window_size), key)
      );

      CREATE TABLE IF NOT EXISTS vitals_stats_seconds(
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

      CREATE TABLE IF NOT EXISTS vitals_stats_minutes(
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

      CREATE TABLE IF NOT EXISTS vitals_node_meta(
        node_id uuid PRIMARY KEY,
        first_report timestamp,
        last_report timestamp,
        hostname text
      );

      CREATE TABLE IF NOT EXISTS vitals_consumers(
        at          timestamp,
        duration    int,
        consumer_id uuid,
        node_id     uuid,
        count       counter,
        PRIMARY KEY((consumer_id, duration), at, node_id)
      );

      CREATE TABLE IF NOT EXISTS workspaces(
        id uuid PRIMARY KEY,
        name text,
        comment text,
        created_at timestamp,
        meta text,
        config text
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

      CREATE TABLE IF NOT EXISTS rbac_users(
        id uuid PRIMARY KEY,
        name text,
        user_token text,
        user_token_ident text,
        comment text,
        enabled boolean,
        created_at timestamp
      );

      CREATE INDEX IF NOT EXISTS ON rbac_users(name);
      CREATE INDEX IF NOT EXISTS ON rbac_users(user_token);
      CREATE INDEX IF NOT EXISTS ON rbac_users(user_token_ident);

      CREATE TABLE IF NOT EXISTS rbac_user_roles(
        user_id uuid,
        role_id uuid,
        PRIMARY KEY(user_id, role_id)
      );

      CREATE INDEX IF NOT EXISTS ON rbac_user_roles(role_id);

      CREATE TABLE IF NOT EXISTS rbac_roles(
        id uuid PRIMARY KEY,
        name text,
        comment text,
        created_at timestamp,
        is_default boolean
      );

      CREATE INDEX IF NOT EXISTS ON rbac_roles(name);
      CREATE INDEX IF NOT EXISTS rbac_role_default_idx on rbac_roles(is_default);

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

      CREATE INDEX IF NOT EXISTS ON rbac_role_entities(entity_type);

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

      -- XXX
      -- this table comes from a migration from the future. At this step is
      -- going to always be empty, but there's already code supporting this
      -- table so I guess we need it here?
      CREATE TABLE IF NOT EXISTS legacy_files(
        id uuid PRIMARY KEY,
        auth boolean,
        name text,
        type text,
        contents text,
        created_at timestamp
      );

      CREATE INDEX IF NOT EXISTS ON legacy_files(name);
      CREATE INDEX IF NOT EXISTS ON legacy_files(type);

      CREATE TABLE IF NOT EXISTS files(
        id uuid PRIMARY KEY,
        path text,
        checksum text,
        contents text,
        created_at timestamp
      );

      CREATE INDEX IF NOT EXISTS ON files(path);

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


      ALTER TABLE consumers ADD type int;

      CREATE INDEX IF NOT EXISTS consumers_type_idx ON consumers(type);

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

      CREATE TABLE IF NOT EXISTS consumer_reset_secrets(
        id uuid PRIMARY KEY,
        consumer_id uuid,
        secret text,
        status int,
        client_addr text,
        created_at timestamp,
        updated_at timestamp
      );

      CREATE INDEX IF NOT EXISTS consumer_reset_secrets_consumer_id_idx ON consumer_reset_secrets (consumer_id);

      CREATE TABLE IF NOT EXISTS developers (
        id          uuid,
        created_at  timestamp,
        updated_at  timestamp,
        consumer_id  uuid,
        rbac_user_id uuid,
        email text,
        status int,
        meta text,
        custom_id text,
        PRIMARY KEY(id)
      );
      CREATE INDEX IF NOT EXISTS developers_email_idx ON developers(email);
      CREATE INDEX IF NOT EXISTS developers_consumer_id_idx ON developers(consumer_id);
      CREATE INDEX IF NOT EXISTS developers_email_idx ON developers(email);
      CREATE INDEX IF NOT EXISTS developers_custom_id_idx ON developers(custom_id);
      CREATE INDEX IF NOT EXISTS developers_rbac_user_id_idx ON developers(rbac_user_id);

      CREATE TABLE IF NOT EXISTS admins (
        id          uuid,
        created_at  timestamp,
        updated_at  timestamp,
        consumer_id  uuid,
        rbac_user_id  uuid,
        rbac_token_enabled boolean,
        email text,
        status int,
        username   text,
        custom_id  text,
        PRIMARY KEY(id)
      );
      CREATE INDEX IF NOT EXISTS admins_consumer_id_idx ON admins(consumer_id);
      CREATE INDEX IF NOT EXISTS admins_rbac_user_id_idx ON admins(rbac_user_id);
      CREATE INDEX IF NOT EXISTS admins_email_idx ON admins(email);
      CREATE INDEX IF NOT EXISTS admins_username_idx ON admins(username);
      CREATE INDEX IF NOT EXISTS admins_custom_id_idx ON admins(custom_id);

      CREATE TABLE IF NOT EXISTS vitals_code_classes_by_workspace(
        workspace_id uuid,
        at timestamp,
        duration int,
        code_class int,
        count counter,
        PRIMARY KEY((workspace_id, duration), at, code_class)
      );

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

      CREATE TABLE IF NOT EXISTS workspace_entity_counters(
        workspace_id uuid,
        entity_type text,
        count counter,
        PRIMARY KEY(workspace_id, entity_type)
      );

      CREATE TABLE IF NOT EXISTS consumers_rbac_users_map(
        consumer_id uuid,
        user_id uuid,
        created_at timestamp,
        PRIMARY KEY (consumer_id, user_id)
      );

      /* Groups Entity */
      CREATE TABLE IF NOT EXISTS groups (
        id          uuid,
        created_at  timestamp,
        name   text,
        comment  text,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS groups_name_idx ON groups(name);

      /* Group and RBAC_Role Mapping */
      CREATE TABLE IF NOT EXISTS group_rbac_roles(
        created_at timestamp,
        group_id uuid,
        rbac_role_id uuid,
        workspace_id uuid,
        PRIMARY KEY (group_id, rbac_role_id)
      );

      CREATE INDEX IF NOT EXISTS group_rbac_roles_rbac_role_id_idx ON group_rbac_roles(rbac_role_id);
      CREATE INDEX IF NOT EXISTS group_rbac_roles_workspace_id_idx ON group_rbac_roles(workspace_id);

      /* License data */
      CREATE TABLE IF NOT EXISTS license_data (
        node_id         uuid,
        req_cnt         counter,
        PRIMARY KEY (node_id)
      );

      /* Login Attempts */
      CREATE TABLE IF NOT EXISTS login_attempts (
        consumer_id uuid,
        attempts map<text,int>,
        created_at  timestamp,
        PRIMARY KEY (consumer_id)
      );

      CREATE TABLE IF NOT EXISTS keyring_meta (
        id            text PRIMARY KEY,
        state         TEXT,
        created_at    timestamp
      );
      CREATE TABLE IF NOT EXISTS keyring_meta_active (
        active text PRIMARY KEY,
        id text
      );

    ]],
    teardown = function(connector)
      -- seeding in cassandra is in teardown phase.
      local seeder = seed_strategies.cassandra
      if not seeder:is_seeded(connector) then
        assert(connector:query(seeder:seed(password)))
      end
    end,
  },
}
