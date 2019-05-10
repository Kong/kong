local utils = require "kong.tools.utils"
local pl_stringx   = require "pl.stringx"

local kong         = kong
local fmt          = string.format
local audit_ttl    = kong.configuration.audit_log_record_ttl

local created_ts = math.floor(ngx.now()) * 1000
local portal_rbac_paths = {
  ['/portal/*']                     = { '/developers/*', '/files/*' },
  ['/portal/developers']            = { '/developers/*' },
  ['/portal/developers/*']          = { '/developers/*' },
  ['/portal/developers/*/*']        = { '/developers/*/*' },
  ['/portal/developers/*/email']    = { '/developers/*/email' },
  ['/portal/developers/*/meta']     = { '/developers/*/meta' },
  ['/portal/developers/*/password'] = { '/developers/*/password' },
  ['/portal/invite']                = { '/developers/invite' },
}


local function replace_portal_rbac_endpoint(row, db_type, connector)
  local res = {}

  local id_formatter = "'%s'"

  if db_type == "cassandra" then
    id_formatter = "%s"
  end

  if not row.created_at and db_type == "cassandra" then
    row.created_at = created_ts
  end

  for _, endpoint_replacement in ipairs(portal_rbac_paths[row.endpoint]) do
    local query_res = assert(connector:query(
      fmt("SELECT role_id FROM rbac_role_endpoints WHERE role_id = " .. id_formatter .. " AND endpoint = '%s' AND workspace = '%s'",
      row.role_id, endpoint_replacement, row.workspace)
    ))

    -- see if modified endpoint already exists
    -- if it does not create a new rbac endpoint
    if not query_res[1] then
      table.insert(res,
        fmt("INSERT into rbac_role_endpoints(role_id, workspace, endpoint, actions, negative, comment, created_at) " ..
            "VALUES(" .. id_formatter .. ", '%s', '%s', %s, %s, '%s', '%s')",
        row.role_id, row.workspace, endpoint_replacement, row.actions, row.negative, row.comment, row.created_at
      ))
    end
  end

  if next(res) then
    local query = table.concat(res, ";")
    assert(connector:query(query))
  end

  -- cleanup stale rbac endpoint
  local delete_query = fmt(
    "DELETE FROM rbac_role_endpoints WHERE role_id = " .. id_formatter .. " AND endpoint = '%s' AND workspace = '%s'",
    row.role_id, row.endpoint, row.workspace
  )
  assert(connector:query(delete_query))
end


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
    consumer.created_at = created_ts
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


local function transform_portal_rbac_routes_postgres(connector)
  for rbac_role_endpoint, err in connector:iterate('SELECT * FROM "rbac_role_endpoints";') do
    if err then
      return nil, err
    end

    if portal_rbac_paths[rbac_role_endpoint.endpoint] then
      replace_portal_rbac_endpoint(rbac_role_endpoint, "postgres", connector)
    end
  end
end


local function transform_portal_rbac_routes_cassandra(connector, coordinator)
  for rows, err in coordinator:iterate("SELECT * FROM rbac_role_endpoints") do
    if err then
      return nil, err
    end

    for _, rbac_role_endpoint in ipairs(rows) do  
      if portal_rbac_paths[rbac_role_endpoint.endpoint] then
        replace_portal_rbac_endpoint(rbac_role_endpoint, "cassandra", connector)
      end
    end
  end
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

local function migrate_legacy_admins(connector, coordinator)
  for map_result, err in coordinator:iterate("SELECT * FROM consumers_rbac_users_map") do
    if err then
      return nil, err
    end
    -- nothing to migrate
    if not map_result[1] then
      return true
    end
    local consumer, err = connector:query("SELECT * FROM consumers WHERE id = " .. map_result[1].consumer_id)

    if err then
      return nil, err
    end
    if not consumer[1] then
      return true
    end

    -- gsub requires a string
    if not consumer[1].custom_id then
      consumer[1].custom_id = ''
    end

    if not consumer[1].username then
      consumer[1].username = ''
    end

    local ok, err = connector:query(
      fmt("INSERT INTO admins(id, created_at, updated_at, consumer_id, rbac_user_id, email, status, username, custom_id) " ..
        "VALUES(%s, '%s', '%s', %s, %s, '%s', %s, '%s', '%s')",
        utils.uuid(),
        consumer[1].created_at,
        consumer[1].created_at,
        map_result[1].consumer_id,
        map_result[1].user_id,
        consumer[1].email,
        consumer[1].status,
        string.gsub(consumer[1].username, "^[a-zA-Z0-9-_~.]*:", ""),
        string.gsub(consumer[1].custom_id, "^[a-zA-Z0-9-_~.]*:", "")
      )
    )

    if not ok then
      return nil, err
    end
  end
  return true
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

        CREATE INDEX IF NOT EXISTS cluster_events_expire_at_idx ON cluster_events(expire_at);

        CREATE INDEX IF NOT EXISTS workspace_entities_idx_entity_id ON workspace_entities(entity_id);

        ALTER TABLE "consumers" DROP CONSTRAINT IF EXISTS "consumers_status_fkey";
        ALTER TABLE "consumers" DROP CONSTRAINT IF EXISTS "consumers_type_fkey";
        ALTER TABLE "credentials" DROP CONSTRAINT IF EXISTS "credentials_consumer_type_fkey";
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

      CREATE TABLE IF NOT EXISTS admins (
        id          uuid,
        created_at  TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        updated_at  TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        consumer_id  uuid references consumers (id),
        rbac_user_id  uuid references rbac_users (id),
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
        consumer_id  uuid references consumers (id) on delete cascade,
        PRIMARY KEY(id)
      );
    ]],

    teardown = function(connector)
      assert(connector:connect_migrations())
      -- migrate legacy admins using consumers_rbac_users_map
      assert(connector:query([[
        INSERT INTO admins(id, rbac_user_id, consumer_id)
        SELECT uuid_in(overlay(overlay(md5(random()::text || ':' || clock_timestamp()::text) placing '4' from 13) placing to_hex(floor(random()*(11-8+1) + 8)::int)::text from 17)::cstring), user_id, consumer_id FROM consumers_rbac_users_map;

        UPDATE admins AS a
          SET email = c.email,
          custom_id = regexp_replace(c.custom_id, '^[a-zA-Z0-9\-\_\~\.]*:','',''), -- custom_id currently formatted as workspace:custom_id
          username = regexp_replace(c.username, '^[a-zA-Z0-9\-\_\~\.]*:','',''), -- username currently formatted as workspace:username
          created_at = c.created_at,
          status = c.status,
          updated_at = now()::timestamp(0)
        FROM consumers AS c
        WHERE a.consumer_id = c.id;
      ]]))

      -- iterate over consumers and create associated developers
      create_developer_table_postgres(connector)

      -- iterate over rbac_role_endpoints and transform changed routes
      transform_portal_rbac_routes_postgres(connector)

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

      assert(connector:query([[
        UPDATE workspaces
        SET config = '{"portal":false}'::json
        WHERE id = '00000000-0000-0000-0000-000000000000'
      ]]))

      -- after the legacy admins are migrated, we don't need this table
      assert(connector:query([[
        DROP TABLE IF EXISTS consumers_rbac_users_map;
      ]]))

    end
  },

  cassandra = {
    up = [[
      CREATE INDEX IF NOT EXISTS ON rbac_user_roles(role_id);

      ALTER TABLE rbac_users ADD user_token_ident text;
      CREATE INDEX IF NOT EXISTS ON rbac_users(user_token_ident);

      CREATE TABLE IF NOT EXISTS developers (
        id          uuid,
        created_at  timestamp,
        updated_at  timestamp,
        consumer_id  uuid,
        email text,
        status int,
        meta text,
        PRIMARY KEY(id)
      );
      CREATE INDEX IF NOT EXISTS developers_email_idx ON developers(email);
      CREATE INDEX IF NOT EXISTS developers_consumer_id_idx ON developers(consumer_id);
      CREATE INDEX IF NOT EXISTS developers_email_idx ON developers(email);

      CREATE TABLE IF NOT EXISTS admins (
        id          uuid,
        created_at  timestamp,
        updated_at  timestamp,
        consumer_id  uuid,
        rbac_user_id  uuid,
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
    ]],

    teardown = function(connector)
      local coordinator = connector:connect_migrations()

      -- migrate admins from consumers via consumers_rbac_users_map
      assert(migrate_legacy_admins(connector, coordinator))

      -- iterate over consumers and create associated developers
      create_developer_table_cassandra(connector, coordinator)
      
      -- iterate over rbac_role_endpoints and transform changed routes
      transform_portal_rbac_routes_cassandra(connector, coordinator)

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

      assert(connector:query([[
        UPDATE workspaces
        SET config = '{"portal":false}'
        WHERE id = 00000000-0000-0000-0000-000000000000
      ]]))

      -- after the legacy admins are migrated, we don't need this table
      assert(connector:query([[
        DROP TABLE IF EXISTS consumers_rbac_users_map;
      ]]))
    end
  }
}
