local utils        = require "kong.tools.utils"
local crypto       = require "kong.plugins.basic-auth.crypto"
local helpers = require "kong.enterprise_edition.db.migrations.helpers"

local fmt = string.format
local created_ts = math.floor(ngx.now()) * 1000

local function detect(f, t)
  for _, v in ipairs(t) do
    local res = f(v)
    if res then
      return res
    end
  end
end


local function seed_kong_admin_data_rbac_pg()
  local password = os.getenv("KONG_PASSWORD")
  if not password then
    return ""
  end

  local password = password
  return fmt([[
    DO $$
    DECLARE kong_admin_user_id uuid;
    DECLARE def_ws_id uuid;
    DECLARE super_admin_role_id uuid;
    DECLARE kong_admin_default_role_id uuid;
    BEGIN

    SELECT uuid_in(overlay(overlay(md5(random()::text || ':' || clock_timestamp()::text) placing '4' from 13) placing to_hex(floor(random()*(11-8+1) + 8)::int)::text from 17)::cstring) into kong_admin_user_id;
    SELECT id into def_ws_id from workspaces where name = 'default';

    -- create kong_admin user
    INSERT INTO rbac_users(id, name, user_token, enabled, comment) VALUES(kong_admin_user_id, 'default:kong_admin', '%s', true, 'Initial RBAC Secure User');
    INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_user_id, 'rbac_users', 'id', kong_admin_user_id);
    INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_user_id, 'rbac_users', 'name', 'kong_admin');
    INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_user_id, 'rbac_users', 'user_token', '%s');


    SELECT id into super_admin_role_id from rbac_roles where name = 'default:super-admin';
    INSERT into rbac_user_roles(user_id, role_id) VALUES(kong_admin_user_id, super_admin_role_id);

    -- create default role for the user
    SELECT uuid_in(overlay(overlay(md5(random()::text || ':' || clock_timestamp()::text) placing '4' from 13) placing to_hex(floor(random()*(11-8+1) + 8)::int)::text from 17)::cstring) into kong_admin_default_role_id;
    INSERT into rbac_roles(id, name, comment, is_default) VALUES(kong_admin_default_role_id, 'default:kong_admin', 'Default user role generated for kong_admin', true);
    INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_default_role_id, 'rbac_roles', 'id', kong_admin_default_role_id);
    INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_default_role_id, 'rbac_roles', 'name', 'kong_admin');
    INSERT into rbac_user_roles(user_id, role_id) VALUES(kong_admin_user_id, kong_admin_default_role_id);

    END $$;
  ]], password, password)
end

local function seed_kong_admin_data_pg()
  local password = os.getenv("KONG_PASSWORD")
  if not password then
    return ""
  end

  local kong_admin_consumer_id = utils.uuid()
  return fmt([[
    DO $$
    DECLARE kong_admin_user_id uuid;
    DECLARE def_ws_id uuid;
    DECLARE super_admin_role_id uuid;
    DECLARE kong_admin_default_role_id uuid;
    DECLARE kong_admin_consumer_id uuid;
    DECLARE kong_admin_admin_id uuid;
    DECLARE kong_admin_basic_auth_id uuid;
    DECLARE kong_rbac_user_id uuid;
    DECLARE tmp record;
    BEGIN

    SELECT uuid_in(overlay(overlay(md5(random()::text || ':' || clock_timestamp()::text) placing '4' from 13) placing to_hex(floor(random()*(11-8+1) + 8)::int)::text from 17)::cstring) into kong_admin_user_id;
    SELECT id into def_ws_id from workspaces where name = 'default';


    -- create the admin consumer
    SELECT * into tmp FROM consumers where username='default:kong_admin' limit 1;
    IF NOT FOUND THEN
        SELECT '%s'::uuid into kong_admin_consumer_id;
        INSERT into consumers(id, username, type, custom_id) VALUES(kong_admin_consumer_id, 'default:kong_admin', 2, 'foo:bar');
        INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_consumer_id, 'consumers', 'id', kong_admin_consumer_id);
        INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_consumer_id, 'consumers', 'username', 'kong_admin');
        INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_consumer_id, 'consumers', 'custom_id', null);
    END IF;

    -- populate consumers_rbac_users_map
    SELECT * into tmp FROM consumers_rbac_users_map where consumer_id=kong_admin_consumer_id limit 1;
    IF NOT FOUND THEN
        SELECT uuid_in(overlay(overlay(md5(random()::text || ':' || clock_timestamp()::text) placing '4' from 13) placing to_hex(floor(random()*(11-8+1) + 8)::int)::text from 17)::cstring) into kong_admin_admin_id;
        SELECT id FROM consumers where username='default:kong_admin' limit 1 into kong_admin_consumer_id;
        SELECT id FROM rbac_users where name='default:kong_admin' limit 1 into kong_rbac_user_id;
        INSERT into consumers_rbac_users_map(consumer_id, user_id) VALUES(kong_admin_consumer_id, kong_rbac_user_id);
        INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_admin_id, 'admins', 'id', kong_admin_admin_id);
        INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_admin_id, 'admins', 'username', 'kong_admin');
        INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_admin_id, 'admins', 'custom_id', null);
        INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_admin_id, 'admins', 'email', null);
    END IF;

    -- create basic-auth credentials
    SELECT * into tmp FROM basicauth_credentials where username='default:kong_admin' limit 1;
    IF NOT FOUND THEN
        SELECT uuid_in(overlay(overlay(md5(random()::text || ':' || clock_timestamp()::text) placing '4' from 13) placing to_hex(floor(random()*(11-8+1) + 8)::int)::text from 17)::cstring) into kong_admin_basic_auth_id;
        INSERT into basicauth_credentials(id, consumer_id, username, password) VALUES(kong_admin_basic_auth_id, kong_admin_consumer_id, 'default:kong_admin', '%s');
        INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_basic_auth_id, 'basicauth_credentials', 'id', kong_admin_basic_auth_id);
        INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_basic_auth_id, 'basicauth_credentials', 'username', 'kong_admin');
    END IF;

    END $$;
  ]], kong_admin_consumer_id, crypto.hash(kong_admin_consumer_id, password))
end

local function seed_kong_admin_data_cas()
  local res = {}
  local super_admin_role_id = utils.uuid()
  local roles = {
    {
      utils.uuid(), "read-only", 'Read access to all endpoints, across all workspaces',
      {"(%s, '*', '*', 1, FALSE)"}
    },
    { utils.uuid(), "admin", 'Full access to all endpoints, across all workspaces-except RBAC Admin API',
      {"(%s, '*', '*', 15, FALSE);",
       "(%s, '*', '/rbac/*', 15, TRUE);",
       "(%s, '*', '/rbac/*/*', 15, TRUE);",
       "(%s, '*', '/rbac/*/*/*', 15, TRUE);",
       "(%s, '*', '/rbac/*/*/*/*', 15, TRUE);",
       "(%s, '*', '/rbac/*/*/*/*/*', 15, TRUE);",
      },
    },
    { super_admin_role_id, "super-admin", 'Full access to all endpoints, across all workspaces',
      {"(%s, '*', '*', 15, FALSE)"}
    }
  }

  for _, role in ipairs(roles) do
    table.insert(res,
      fmt("INSERT into rbac_roles(id, name, comment, created_at) VALUES(%s, 'default:%s', '%s', '%s')",
        role[1] , role[2], role[3], created_ts))
    helpers.add_to_default_ws(res, role[1], "rbac_roles", "id", role[1])
    helpers.add_to_default_ws(res, role[1], "rbac_roles", "name", role[2])

    for _, endpoint in ipairs(role[4]) do
      table.insert(res,
        fmt(
          fmt("INSERT INTO rbac_role_endpoints(role_id, workspace, endpoint, actions, negative) VALUES %s", endpoint),
          role[1]))
    end
  end

  local password = os.getenv("KONG_PASSWORD")

  if password then
    local password = password

    local kong_admin_rbac_id = utils.uuid()
    -- create kong_admin RBAC user
    table.insert(res,
      fmt("INSERT into rbac_users(id, name, user_token, enabled, comment, created_at) VALUES(%s, 'default:%s', '%s', %s, '%s', %s)",
        kong_admin_rbac_id, "kong_admin", password, 'true', "Initial RBAC Secure User", created_ts))
    helpers.add_to_default_ws(res, kong_admin_rbac_id, "rbac_users", "id", kong_admin_rbac_id)
    helpers.add_to_default_ws(res, kong_admin_rbac_id, "rbac_users", "name", "kong_admin")
    helpers.add_to_default_ws(res, kong_admin_rbac_id, "rbac_users", "user_token", password)

    -- add user-roles relation
    table.insert(res,
      fmt("INSERT into rbac_user_roles(user_id, role_id) VALUES(%s, %s)",
        kong_admin_rbac_id, super_admin_role_id))

    --create default role for the user
    local kong_admin_rbac_default_role_id = utils.uuid()
    table.insert(res,
      fmt("INSERT into rbac_roles(id, name, comment, is_default, created_at) VALUES(%s, 'default:%s', '%s', %s, %s)",
        kong_admin_rbac_default_role_id , "kong_admin", "Default user role generated for kong_admin", 'true', created_ts))
    helpers.add_to_default_ws(res, kong_admin_rbac_default_role_id, "rbac_roles", "id", kong_admin_rbac_default_role_id)
    helpers.add_to_default_ws(res, kong_admin_rbac_default_role_id, "rbac_roles", "name", "kong_admin")

    table.insert(res,
      fmt("INSERT into rbac_user_roles(user_id, role_id) VALUES(%s, %s)",
        kong_admin_rbac_id, kong_admin_rbac_default_role_id))


    -- create the admin consumer
    local kong_admin_consumer_id = utils.uuid()
    table.insert(res,
      fmt("INSERT into consumers(id, username, type, created_at, status, custom_id) VALUES(%s, 'default:%s', %s, %s, %s, 'default:%s')",
        kong_admin_consumer_id, "kong_admin", 2, created_ts, 0, 'bar'))

    helpers.add_to_default_ws(res, kong_admin_consumer_id, "consumers", "id", kong_admin_consumer_id)
    helpers.add_to_default_ws(res, kong_admin_consumer_id, "consumers", "username", "kong_admin")
    helpers.add_to_default_ws(res, kong_admin_consumer_id, "consumers", "custom_id", nil)

    -- add bootstrapped admin to consumers_rbac_users_map
    table.insert(res,
    fmt("INSERT into consumers_rbac_users_map(consumer_id, user_id, created_at) VALUES(%s, %s, %s)",
      kong_admin_consumer_id, kong_admin_rbac_id, created_ts))

    -- create basic-auth credential for admin
    local kong_admin_basic_auth_id = utils.uuid()
    table.insert(res,
      fmt("INSERT into basicauth_credentials(id, consumer_id, username, password, created_at)" ..
        "VALUES(%s , %s, 'default:%s', '%s', %s)",
          kong_admin_basic_auth_id, kong_admin_consumer_id, "kong_admin", crypto.hash(kong_admin_consumer_id, password), created_ts))

    helpers.add_to_default_ws(res, kong_admin_basic_auth_id, "basicauth_credentials", "id", kong_admin_basic_auth_id)
    helpers.add_to_default_ws(res, kong_admin_basic_auth_id, "basicauth_credentials", "username", "kong_admin")
  end

  return table.concat(res, ";") .. ";"
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
        created_at                TIMESTAMP WITHOUT TIME ZONE DEFAULT timezone('utc'::text, ('now'::text)::timestamp(0) with time zone),
        meta                      JSON                      DEFAULT '{}'::json,
        config                    JSON                      DEFAULT '{"portal":false}'::json
      );

      INSERT INTO workspaces(id, name, config)
      VALUES ('00000000-0000-0000-0000-000000000000', 'default', '{"portal":true}'::json) ON CONFLICT DO NOTHING;

      CREATE TABLE IF NOT EXISTS workspace_entities(
        workspace_id uuid,
        workspace_name text,
        entity_id text,
        entity_type text,
        unique_field_name text,
        unique_field_value text,
        PRIMARY KEY(workspace_id, entity_id, unique_field_name)
      );

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
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        is_default boolean default false
      );

      CREATE INDEX IF NOT EXISTS rbac_roles_name_idx on rbac_roles(name);
      CREATE INDEX IF NOT EXISTS rbac_role_default_idx on rbac_roles(is_default);

      CREATE TABLE IF NOT EXISTS rbac_role_entities(
        role_id uuid,
        entity_id text,
        entity_type text NOT NULL,
        actions smallint NOT NULL,
        negative boolean NOT NULL,
        comment text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY(role_id, entity_id)
      );

      CREATE TABLE IF NOT EXISTS consumers_rbac_users_map(
        consumer_id uuid REFERENCES consumers (id) ON DELETE CASCADE,
        user_id uuid REFERENCES rbac_users (id) ON DELETE CASCADE,
        created_at timestamp without time zone DEFAULT timezone('utc'::text, ('now'::text)::timestamp(0) with time zone),
        PRIMARY KEY (consumer_id, user_id)
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



      CREATE TABLE IF NOT EXISTS files(
        id uuid PRIMARY KEY,
        auth boolean NOT NULL,
        name text UNIQUE NOT NULL,
        type text NOT NULL,
        contents text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );

      CREATE INDEX IF NOT EXISTS portal_files_name_idx on files(name);

      DO $$
      BEGIN
        IF not EXISTS (SELECT column_name
               FROM information_schema.columns
               WHERE table_schema='public' and table_name='consumers' and column_name='type') THEN
          ALTER TABLE consumers
            ADD COLUMN type int NOT NULL DEFAULT 0,
            ADD COLUMN email text,
            ADD COLUMN status integer,
            ADD COLUMN meta text;

            ALTER TABLE consumers ADD CONSTRAINT consumers_email_type_key UNIQUE(email, type);
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


      CREATE TABLE IF NOT EXISTS audit_objects(
        id uuid PRIMARY KEY,
        request_id char(32),
        entity_key uuid,
        dao_name text NOT NULL,
        operation char(6) NOT NULL,
        entity text,
        rbac_user_id uuid,
        signature text,
        expire timestamp without time zone
      );

      DO $$
      BEGIN
          IF (SELECT to_regclass('idx_audit_objects_expire')) IS NULL THEN
              CREATE INDEX idx_audit_objects_expire on audit_objects(expire);
          END IF;
      END$$;

      CREATE OR REPLACE FUNCTION delete_expired_audit_objects() RETURNS trigger
          LANGUAGE plpgsql
          AS $$
      BEGIN
          DELETE FROM audit_objects WHERE expire <= NOW();
          RETURN NEW;
      END;
      $$;

      DO $$
      BEGIN
          IF NOT EXISTS(
              SELECT FROM information_schema.triggers
               WHERE event_object_table = 'audit_objects'
                 AND trigger_name = 'delete_expired_audit_objects_trigger')
          THEN
              CREATE TRIGGER delete_expired_audit_objects_trigger
               AFTER INSERT on audit_objects
               EXECUTE PROCEDURE delete_expired_audit_objects();
          END IF;
      END;
      $$;

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
        expire timestamp without time zone
      );

      DO $$
      BEGIN
          IF (SELECT to_regclass('idx_audit_requests_expire')) IS NULL THEN
              CREATE INDEX idx_audit_requests_expire on audit_requests(expire);
          END IF;
      END$$;

      CREATE OR REPLACE FUNCTION delete_expired_audit_requests() RETURNS trigger
          LANGUAGE plpgsql
          AS $$
      BEGIN
          DELETE FROM audit_requests WHERE expire <= NOW();
          RETURN NEW;
      END;
      $$;

      DO $$
      BEGIN
          IF NOT EXISTS(
              SELECT FROM information_schema.triggers
               WHERE event_object_table = 'audit_requests'
                 AND trigger_name = 'delete_expired_audit_requests_trigger')
          THEN
              CREATE TRIGGER delete_expired_audit_requests_trigger
               AFTER INSERT on audit_requests
               EXECUTE PROCEDURE delete_expired_audit_requests();
          END IF;
      END;
      $$;

-- read-only role
DO $$
DECLARE lastid uuid;
DECLARE def_ws_id uuid;
DECLARE tmp record;
BEGIN

SELECT uuid_in(overlay(overlay(md5(random()::text || ':' || clock_timestamp()::text) placing '4' from 13) placing to_hex(floor(random()*(11-8+1) + 8)::int)::text from 17)::cstring) into lastid;
SELECT id into def_ws_id from workspaces where name = 'default';

SELECT * into tmp FROM rbac_roles WHERE name='default:read-only' LIMIT 1;

IF NOT FOUND THEN
  INSERT INTO rbac_roles(id, name, comment)
  VALUES (lastid, 'default:read-only', 'Read access to all endpoints, across all workspaces');

  INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value)
  VALUES (def_ws_id, 'default', lastid, 'rbac_roles', 'name', 'read-only');

  INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value)
  VALUES (def_ws_id, 'default', lastid, 'rbac_roles', 'id', lastid);


  INSERT INTO rbac_role_endpoints(role_id, workspace, endpoint, actions, negative)
  VALUES (lastid, '*', '*', 1, FALSE);
END IF;

END $$;


-- admin role
DO $$
DECLARE lastid uuid;
DECLARE def_ws_id uuid;
DECLARE tmp record;
BEGIN

SELECT uuid_in(overlay(overlay(md5(random()::text || ':' || clock_timestamp()::text) placing '4' from 13) placing to_hex(floor(random()*(11-8+1) + 8)::int)::text from 17)::cstring) into lastid;
SELECT id into def_ws_id from workspaces where name = 'default';

SELECT * into tmp FROM rbac_roles WHERE name='default:admin' LIMIT 1;

IF NOT FOUND THEN
  INSERT INTO rbac_roles(id, name, comment)
  VALUES (lastid, 'default:admin', 'Full access to all endpoints, across all workspaces—except RBAC Admin API');

  INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value)
  VALUES (def_ws_id, 'default', lastid, 'rbac_roles', 'name', 'admin');

  INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value)
  VALUES (def_ws_id, 'default', lastid, 'rbac_roles', 'id', lastid);


  INSERT INTO rbac_role_endpoints(role_id, workspace, endpoint, actions, negative)
  VALUES (lastid, '*', '*', 15, FALSE);

  INSERT INTO rbac_role_endpoints(role_id, workspace, endpoint, actions, negative)
  VALUES (lastid, '*', '/rbac/*', 15, TRUE);

  INSERT INTO rbac_role_endpoints(role_id, workspace, endpoint, actions, negative)
  VALUES (lastid, '*', '/rbac/*/*', 15, TRUE);

  INSERT INTO rbac_role_endpoints(role_id, workspace, endpoint, actions, negative)
  VALUES (lastid, '*', '/rbac/*/*/*', 15, TRUE);

  INSERT INTO rbac_role_endpoints(role_id, workspace, endpoint, actions, negative)
  VALUES (lastid, '*', '/rbac/*/*/*/*', 15, TRUE);

  INSERT INTO rbac_role_endpoints(role_id, workspace, endpoint, actions, negative)
  VALUES (lastid, '*', '/rbac/*/*/*/*/*', 15, TRUE);
END IF;

END $$;

-- super-admin role
DO $$
DECLARE lastid uuid;
DECLARE def_ws_id uuid;
DECLARE tmp record;
BEGIN

SELECT uuid_in(overlay(overlay(md5(random()::text || ':' || clock_timestamp()::text) placing '4' from 13) placing to_hex(floor(random()*(11-8+1) + 8)::int)::text from 17)::cstring) into lastid;
SELECT id into def_ws_id from workspaces where name = 'default';

SELECT * into tmp FROM rbac_roles WHERE name='default:super-admin' LIMIT 1;

IF NOT FOUND THEN
  INSERT INTO rbac_roles(id, name, comment)
  VALUES (lastid, 'default:super-admin', 'Full access to all endpoints, across all workspaces');

  INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value)
  VALUES (def_ws_id, 'default', lastid, 'rbac_roles', 'name', 'super-admin');

  INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value)
  VALUES (def_ws_id, 'default', lastid, 'rbac_roles', 'id', lastid);


  INSERT INTO rbac_role_endpoints(role_id, workspace, endpoint, actions, negative)
  VALUES (lastid, '*', '*', 15, FALSE);
END IF;

END $$;
    ]] .. seed_kong_admin_data_rbac_pg() .. seed_kong_admin_data_pg()
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

      INSERT INTO workspaces(id, name, config, meta)
      VALUES (00000000-0000-0000-0000-000000000000, 'default', '{"portal":true}', '{}');

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

      CREATE TABLE IF NOT EXISTS files(
        id uuid PRIMARY KEY,
        auth boolean,
        name text,
        type text,
        contents text,
        created_at timestamp
      );

      CREATE INDEX IF NOT EXISTS ON files(name);
      CREATE INDEX IF NOT EXISTS ON files(type);

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
      ALTER TABLE consumers ADD email text;
      ALTER TABLE consumers ADD status int;
      ALTER TABLE consumers ADD meta text;

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

      CREATE INDEX IF NOT EXISTS ON rbac_role_entities(entity_type);

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
    ]],
    teardown = function(connector)
      local coordinator = connector:connect_migrations()

      -- create default workspace if doesn't exist
      for rows, err in coordinator:iterate("select * from workspaces") do
        if not detect(function(x) return x.name == "default" end, rows) then
          connector:query([[INSERT INTO workspaces(id, name)
            VALUES (00000000-0000-0000-0000-000000000000, 'default');]])
        end
      end

      -- create default roles if they do not exist (checking for read-only one)
      local read_only_present = connector:query([[
        SELECT * FROM rbac_roles WHERE name='default:read-only';
      ]])
      if not (read_only_present and read_only_present[1]) then
        assert(connector:query(seed_kong_admin_data_cas()))
      end
    end
  },
}
