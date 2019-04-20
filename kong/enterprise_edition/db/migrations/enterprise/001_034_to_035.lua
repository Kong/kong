local utils = require "kong.tools.utils"
local pl_stringx   = require "pl.stringx"


local kong         = kong
local fmt          = string.format
local ngx_utc_time = ngx.utctime
local audit_ttl    = kong.configuration.audit_log_record_ttl


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

    ALTER TABLE rbac_users
        ADD COLUMN user_token_ident text;

      DO $$
      BEGIN
        IF (SELECT to_regclass('idx_rbac_token_ident')) IS NULL THEN
        CREATE INDEX idx_rbac_token_ident on rbac_users(user_token_ident);
        END IF;
      END$$;
    ]],

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

      ALTER TABLE rbac_users ADD user_token_ident text;
      CREATE INDEX IF NOT EXISTS ON rbac_users(user_token_ident);
    ]],

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
