local utils = require "kong.tools.utils"
local pl_stringx   = require "pl.stringx"
local rbac         = require "kong.rbac"
local bcrypt       = require "bcrypt"
local crypto       = require "kong.plugins.basic-auth.crypto"


local kong         = kong
local fmt          = string.format
local ngx_utc_time = ngx.utctime
local audit_ttl    = kong.configuration.audit_log_record_ttl

local LOG_ROUNDS = 9

local function build_developer_queries(res, consumer, db_type, connector)
  local developer_id = utils.uuid()
  local developer_email = consumer.username
  local workspace_name = pl_stringx.split(consumer.username, ":")[1]
  local workspace = assert(connector:query("SELECT * from workspaces where name = '" .. workspace_name .. "';"))[1]

  local id_formatter = "'%s'"

  if db_type == "cassandra" then
    id_formatter = "%s"
  end

  if not consumer.created_at and db_type == "cassandra" then
    consumer.created_at = ngx_utc_time()
  end

  table.insert(res,
    fmt("INSERT into developers(id, consumer_id, created_at, email, status, meta) " ..
        "VALUES(" .. id_formatter .. ", " .. id_formatter .. ", '%s', '%s', %s, '%s')",
    developer_id, consumer.id, consumer.created_at, consumer.username, consumer.status, consumer.meta
  ))

  table.insert(res,
    fmt("INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) " ..
        "VALUES(" .. id_formatter .. ", '%s', '%s', 'developers', 'id', '%s')",
    workspace.id, workspace.name, developer_id, developer_id
  ))

  table.insert(res,
    fmt("INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value)" ..
        "VALUES(" .. id_formatter .. ", '%s', '%s', 'developers', 'email', '%s')",
    workspace.id, workspace.name, developer_id, developer_email
  ))
end


local function create_developer_table_postgres(connector)
  local res = {}

  for consumer, err in connector:iterate('SELECT * FROM "consumers";') do
    if err then
      return nil, err
    end

    if consumer.type == 1 then
      build_developer_queries(res, consumer, "postgres", connector)
    end
  end

  if next(res) then
    local query = table.concat(res, ";")
    assert(connector:query(query))
  end
end


local function create_developer_table_cassandra(connector, coordinator)
  local res = {}

  for rows, err in coordinator:iterate("SELECT * FROM consumers") do
    if err then
      return nil, err
    end

    for _, consumer in ipairs(rows) do

      if consumer.type == 1 then
        build_developer_queries(res, consumer, "cassandra", connector)
      end
    end
  end

  if next(res) then
    local query = table.concat(res, ";")
    assert(connector:query(query))
  end
end


local function seed_kong_admin_data_cas()
  local res = {}
  local def_ws_id = '00000000-0000-0000-0000-000000000000'
  local super_admin_role_id = utils.uuid()

  local function add_to_default_ws(id, type, field_name, field_value)
    if field_value then
      table.insert(res,
        fmt("INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(%s, 'default', '%s', '%s', '%s', '%s')",
          def_ws_id, id, type, field_name, field_value))
    else
      table.insert(res,
        fmt("INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(%s, 'default', '%s', '%s', '%s', null)",
          def_ws_id, id, type, field_name))
    end
  end

  local roles = {
    {
      utils.uuid(), "read-only", 'Read access to all endpoints, across all workspaces',
      {"(%s, '*', '*', 1, FALSE)"}
    },
    { utils.uuid(), "admin", 'Full access to all endpoints, across all workspaces—except RBAC Admin API',
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
      fmt("INSERT into rbac_roles(id, name, comment) VALUES(%s, 'default:%s', '%s')",
        role[1] , role[2], role[3]))
    add_to_default_ws(role[1], "rbac_roles", "id", role[1])
    add_to_default_ws(role[1], "rbac_roles", "name", role[2])

    for _, endpoint in ipairs(role[4]) do
      table.insert(res,
        fmt(
          fmt("INSERT INTO rbac_role_endpoints(role_id, workspace, endpoint, actions, negative) VALUES %s", endpoint),
          role[1]))
    end
  end

  --seed kong_admin
  local password = os.getenv("KONG_PASSWORD")

  if password then
    local digest = bcrypt.digest(password, LOG_ROUNDS)

    local kong_admin_rbac_id = utils.uuid()
    -- create kong_admin RBAC user
    table.insert(res,
      fmt("INSERT into rbac_users(id, name, user_token, user_token_ident, enabled, comment) VALUES(%s, 'default:%s', '%s', '%s', %s, '%s')",
        kong_admin_rbac_id, "kong_admin", digest, rbac.get_token_ident(password), 'true', "Initial RBAC Secure User"))
    add_to_default_ws(kong_admin_rbac_id, "rbac_users", "id", kong_admin_rbac_id)
    add_to_default_ws(kong_admin_rbac_id, "rbac_users", "name", "kong_admin")

    -- add user-roles relation
    table.insert(res,
      fmt("INSERT into rbac_user_roles(user_id, role_id) VALUES(%s, %s)",
        kong_admin_rbac_id , super_admin_role_id))

    --create default role for the user
    local kong_admin_rbac_default_role_id =  utils.uuid()
    table.insert(res,
      fmt("INSERT into rbac_roles(id, name, comment, is_default) VALUES(%s, 'default:%s', '%s', %s)",
        kong_admin_rbac_default_role_id , "kong_admin", "Default user role generated for kong_admin", 'true'))
    add_to_default_ws(kong_admin_rbac_default_role_id, "rbac_roles", "id", kong_admin_rbac_default_role_id)
    add_to_default_ws(kong_admin_rbac_default_role_id, "rbac_roles", "name", "kong_admin")

    table.insert(res,
      fmt("INSERT into rbac_user_roles(user_id, role_id) VALUES(%s, %s)",
        kong_admin_rbac_id , kong_admin_rbac_default_role_id))


    -- create kong_admin user
    local kong_admin_id = utils.uuid()
    table.insert(res,
      fmt("INSERT into rbac_users(id, name, user_token, user_token_ident, enabled, comment) VALUES(%s, 'default:%s-%s', '%s', '%s', %s, '%s')",
        kong_admin_id, "kong_admin", kong_admin_id, digest, rbac.get_token_ident(password), 'true', "Initial RBAC Secure User"))
    add_to_default_ws(kong_admin_id, "rbac_users", "id", kong_admin_id)
    add_to_default_ws(kong_admin_id, "rbac_users", "name", "kong_admin-" .. kong_admin_id)

    -- add user-roles relation
    table.insert(res,
      fmt("INSERT into rbac_user_roles(user_id, role_id) VALUES(%s, %s)",
        kong_admin_id , super_admin_role_id))

    --create default role for the user
    local kong_admin_default_role_id =  utils.uuid()
    table.insert(res,
      fmt("INSERT into rbac_roles(id, name, comment, is_default) VALUES(%s, 'default:%s-%s', '%s', %s)",
        kong_admin_default_role_id , "kong_admin", kong_admin_id, "Default user role generated for kong_admin", 'true'))
    add_to_default_ws(kong_admin_default_role_id, "rbac_roles", "id", kong_admin_default_role_id)
    add_to_default_ws(kong_admin_default_role_id, "rbac_roles", "name", "kong_admin")

    table.insert(res,
      fmt("INSERT into rbac_user_roles(user_id, role_id) VALUES(%s, %s)",
        kong_admin_id , kong_admin_default_role_id))

    -- create the admin consumer

    local kong_admin_consumer_id =  utils.uuid()
    table.insert(res,
      fmt("INSERT into consumers(id, username, type, created_at) VALUES(%s, 'default:%s', %s, toUnixTimestamp(now()))",
        kong_admin_consumer_id , "kong_admin", 2))

    add_to_default_ws(kong_admin_consumer_id, "consumers", "id", kong_admin_consumer_id)
    add_to_default_ws(kong_admin_consumer_id, "consumers", "username", "kong_admin")
    add_to_default_ws(kong_admin_consumer_id, "consumers", "custom_id", nil)

    -- create admin
    local kong_admin_admin_id =  utils.uuid()
    table.insert(res,
      fmt("INSERT into admins(id, consumer_id, rbac_user_id, status, username, created_at)" ..
        "VALUES(%s , %s, %s, %s, '%s', toUnixTimestamp(now()))",
        kong_admin_admin_id , kong_admin_consumer_id, kong_admin_id, 0, "kong_admin"))

    add_to_default_ws(kong_admin_admin_id, "admins", "id", kong_admin_admin_id)
    add_to_default_ws(kong_admin_admin_id, "admins", "username", "kong_admin")
    add_to_default_ws(kong_admin_admin_id, "admins", "custom_id", nil)
    add_to_default_ws(kong_admin_admin_id, "admins", "email", nil)

    -- create basic-auth credential for admin
    local kong_admin_basic_auth_id = utils.uuid()
    table.insert(res,
      fmt("INSERT into basicauth_credentials(id, consumer_id, username, password, created_at)" ..
        "VALUES(%s , %s, 'default:%s', '%s', toUnixTimestamp(now()))",
        kong_admin_basic_auth_id , kong_admin_consumer_id, "kong_admin", crypto.encrypt(kong_admin_consumer_id, password)))

    add_to_default_ws(kong_admin_basic_auth_id, "basicauth_credentials", "id", kong_admin_basic_auth_id)
    add_to_default_ws(kong_admin_basic_auth_id, "basicauth_credentials", "username", "kong_admin")
  end

  return table.concat(res, ";") .. ';'
end


local function seed_kong_admin_data_pg()
  local password = os.getenv("KONG_PASSWORD")
  if not password then
    return ""
  end

  local random_password = utils.random_string()
  local digest = bcrypt.digest(random_password, LOG_ROUNDS)
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
    BEGIN

    SELECT uuid_in(overlay(overlay(md5(random()::text || ':' || clock_timestamp()::text) placing '4' from 13) placing to_hex(floor(random()*(11-8+1) + 8)::int)::text from 17)::cstring) into kong_admin_user_id;
    SELECT id into def_ws_id from workspaces where name = 'default';


    -- create kong_admin user
    INSERT INTO rbac_users(id, name, user_token, user_token_ident, enabled, comment) VALUES(kong_admin_user_id, CONCAT('default:kong_admin-', kong_admin_user_id::varchar), '%s', '%s', true, 'Initial RBAC Secure User');
    INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_user_id, 'rbac_users', 'id', kong_admin_user_id);
    INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_user_id, 'rbac_users', 'name', CONCAT('kong_admin-', kong_admin_user_id::varchar));


    SELECT id into super_admin_role_id from rbac_roles where name = 'default:super-admin';
    INSERT into rbac_user_roles(user_id, role_id) VALUES(kong_admin_user_id, super_admin_role_id);

    -- create default role for the user
    SELECT uuid_in(overlay(overlay(md5(random()::text || ':' || clock_timestamp()::text) placing '4' from 13) placing to_hex(floor(random()*(11-8+1) + 8)::int)::text from 17)::cstring) into kong_admin_default_role_id;
    INSERT into rbac_roles(id, name, comment, is_default) VALUES(kong_admin_default_role_id, CONCAT('default:kong_admin-', kong_admin_user_id::varchar), 'Default user role generated for kong_admin', true);
    INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_default_role_id, 'rbac_roles', 'id', kong_admin_default_role_id);
    INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_default_role_id, 'rbac_roles', 'name', CONCAT('kong_admin-', kong_admin_user_id::varchar));
    INSERT into rbac_user_roles(user_id, role_id) VALUES(kong_admin_user_id, kong_admin_default_role_id);

    -- create the admin consumer
    SELECT '%s'::uuid into kong_admin_consumer_id;
    INSERT into consumers(id, username, type) VALUES(kong_admin_consumer_id, 'default:kong_admin', 2);
    INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_consumer_id, 'consumers', 'id', kong_admin_consumer_id);
    INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_consumer_id, 'consumers', 'username', 'kong_admin');
    INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_consumer_id, 'consumers', 'custom_id', null);

    -- create admin
    SELECT uuid_in(overlay(overlay(md5(random()::text || ':' || clock_timestamp()::text) placing '4' from 13) placing to_hex(floor(random()*(11-8+1) + 8)::int)::text from 17)::cstring) into kong_admin_admin_id;
    INSERT into admins(id, consumer_id, rbac_user_id, status, username) VALUES(kong_admin_admin_id , kong_admin_consumer_id, kong_admin_user_id, 0, 'kong_admin');
    INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_admin_id, 'admins', 'id', kong_admin_admin_id);
    INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_admin_id, 'admins', 'username', 'kong_admin');
    INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_admin_id, 'admins', 'custom_id', null);
    INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_admin_id, 'admins', 'email', null);

    -- create basic-auth credentials
    SELECT uuid_in(overlay(overlay(md5(random()::text || ':' || clock_timestamp()::text) placing '4' from 13) placing to_hex(floor(random()*(11-8+1) + 8)::int)::text from 17)::cstring) into kong_admin_basic_auth_id;
    INSERT into basicauth_credentials(id, consumer_id, username, password, created_at) VALUES(kong_admin_basic_auth_id, kong_admin_consumer_id, 'default:kong_admin', '%s', now());
    INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_basic_auth_id, 'basicauth_credentials', 'id', kong_admin_basic_auth_id);
    INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_basic_auth_id, 'basicauth_credentials', 'username', 'kong_admin');

    END $$;
  ]], digest, rbac.get_token_ident(random_password), kong_admin_consumer_id, crypto.encrypt(kong_admin_consumer_id, password))
end


local function seed_kong_admin_data_rbac_pg()
  local password = os.getenv("KONG_PASSWORD")
  if not password then
    return ""
  end

  local digest = bcrypt.digest(password, LOG_ROUNDS)
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
    INSERT INTO rbac_users(id, name, user_token, user_token_ident, enabled, comment) VALUES(kong_admin_user_id, 'default:kong_admin', '%s', '%s', true, 'Initial RBAC Secure User');
    INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_user_id, 'rbac_users', 'id', kong_admin_user_id);
    INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_user_id, 'rbac_users', 'name', 'kong_admin');


    SELECT id into super_admin_role_id from rbac_roles where name = 'default:super-admin';
    INSERT into rbac_user_roles(user_id, role_id) VALUES(kong_admin_user_id, super_admin_role_id);

    -- create default role for the user
    SELECT uuid_in(overlay(overlay(md5(random()::text || ':' || clock_timestamp()::text) placing '4' from 13) placing to_hex(floor(random()*(11-8+1) + 8)::int)::text from 17)::cstring) into kong_admin_default_role_id;
    INSERT into rbac_roles(id, name, comment, is_default) VALUES(kong_admin_default_role_id, 'default:kong_admin', 'Default user role generated for kong_admin', true);
    INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_default_role_id, 'rbac_roles', 'id', kong_admin_default_role_id);
    INSERT INTO workspace_entities(workspace_id, workspace_name, entity_id, entity_type, unique_field_name, unique_field_value) VALUES(def_ws_id, 'default', kong_admin_default_role_id, 'rbac_roles', 'name', 'kong_admin');
    INSERT into rbac_user_roles(user_id, role_id) VALUES(kong_admin_user_id, kong_admin_default_role_id);

    END $$;
  ]], digest, rbac.get_token_ident(password))
end


return {
  postgres = {
    up = [[
     DO $$
     BEGIN
     ALTER TABLE IF EXISTS ONLY "rbac_user_roles"
       ADD CONSTRAINT rbac_user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES rbac_roles(id) ON DELETE CASCADE;

     ALTER TABLE IF EXISTS ONLY "rbac_user_roles"
       ADD CONSTRAINT rbac_user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES rbac_users(id) ON DELETE CASCADE;

     ALTER TABLE IF EXISTS ONLY "rbac_role_entities"
       ADD CONSTRAINT rbac_role_entities_role_id_fkey FOREIGN KEY (role_id) REFERENCES rbac_roles(id) ON DELETE CASCADE;

     CREATE INDEX IF NOT EXISTS rbac_role_entities_role_idx on rbac_role_entities(role_id);

     ALTER TABLE IF EXISTS ONLY "rbac_role_endpoints"
       ADD CONSTRAINT rbac_role_endpoints_role_id_fkey FOREIGN KEY (role_id) REFERENCES rbac_roles(id) ON DELETE CASCADE;

     CREATE INDEX IF NOT EXISTS rbac_role_endpoints_role_idx on rbac_role_endpoints(role_id);

     ALTER TABLE "consumers" DROP COLUMN IF EXISTS status;
     ALTER TABLE "consumers" DROP CONSTRAINT IF EXISTS "consumers_type_fkey";
     ALTER TABLE "credentials" DROP CONSTRAINT IF EXISTS "consumers_type_fkey";
     DROP TABLE IF EXISTS consumer_statuses;
     DROP TABLE IF EXISTS consumer_types;

     END
     $$;

     ALTER TABLE audit_objects
        ADD COLUMN ttl timestamp WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0)
          AT TIME ZONE 'UTC' + INTERVAL ']] .. audit_ttl .. [[');

     ALTER TABLE audit_requests
        ADD COLUMN ttl timestamp WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP(0)
          AT TIME ZONE 'UTC' + INTERVAL ']] .. audit_ttl .. [[');
    ]] .. seed_kong_admin_data_rbac_pg() .. seed_kong_admin_data_pg(),

    teardown = function(connector)
      assert(connector:connect_migrations())

      -- iterate over consumers and create associated developers
      create_developer_table_postgres(connector)

      -- remove unneccesssary columns in consumers
      assert(connector:query([[
        ALTER TABLE consumers DROP COLUMN IF EXISTS meta;
        ALTER TABLE consumers DROP COLUMN IF EXISTS email;
        ALTER TABLE consumers DROP COLUMN IF EXISTS status;
      ]]))

      assert(connector:query([[
        ALTER TABLE audit_objects
          DROP COLUMN expire;

        DROP TRIGGER delete_expired_audit_objects_trigger ON audit_objects;
        DROP FUNCTION delete_expired_audit_objects();

        ALTER TABLE audit_requests
          DROP COLUMN expire;

        DROP TRIGGER delete_expired_audit_requests_trigger ON audit_requests;
        DROP FUNCTION delete_expired_audit_requests();
      ]]))

    end
  },

  cassandra = {
    up = [[
      CREATE INDEX IF NOT EXISTS ON rbac_user_roles(role_id);
    ]] .. seed_kong_admin_data_cas(),

    teardown = function(connector)
      local coordinator = connector:connect_migrations()

      -- iterate over consumers and create associated developers
      create_developer_table_cassandra(connector, coordinator)

      -- remove unneccesssary columns in consumers
      assert(connector:query([[
        DROP INDEX IF EXISTS consumers_status_idx;

        ALTER TABLE consumers DROP status;
        ALTER TABLE consumers DROP email;
        ALTER TABLE consumers DROP meta;
      ]]))

      assert(connector:query([[
        ALTER TABLE audit_requests DROP expire;
      ]]))
    end
  }
}
