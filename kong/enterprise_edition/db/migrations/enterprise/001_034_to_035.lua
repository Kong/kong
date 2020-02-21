local utils = require "kong.tools.utils"
local pl_stringx   = require "pl.stringx"
local cassandra = require "cassandra"

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
    for i=1,#map_result do
      local consumer, err = connector:query("SELECT * FROM consumers WHERE id = " .. map_result[i].consumer_id)

      if err then
        return nil, err
      end
      if not consumer[1] then
        return true
      end

      if not consumer[1].custom_id then
        consumer[1].custom_id = cassandra.null
      else
        consumer[1].custom_id = string.gsub(consumer[1].custom_id, "^[a-zA-Z0-9-_~.]*:", "")
      end

      if not consumer[1].username then
        consumer[1].username = cassandra.null
      else
        consumer[1].username = string.gsub(consumer[1].username, "^[a-zA-Z0-9-_~.]*:", "")
      end

      if not consumer[1].email then
        consumer[1].email = cassandra.null
      end

      local ok, err = connector:query("INSERT INTO admins(id, created_at, updated_at, consumer_id, rbac_user_id, status, username, custom_id, email)" ..
          "VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)", {
          cassandra.uuid(utils.uuid()),
          cassandra.timestamp(consumer[1].created_at),
          cassandra.timestamp(consumer[1].created_at),
          cassandra.uuid(map_result[i].consumer_id),
          cassandra.uuid(map_result[i].user_id),
          consumer[1].status,
          consumer[1].username,
          consumer[1].custom_id,
          consumer[1].email
      })
      if not ok then
        return nil, err
      end
    end
  end
  return true
end

return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        -- No idea
        -- ALTER TABLE "consumers" DROP CONSTRAINT IF EXISTS "consumers_status_fkey";
        -- ALTER TABLE "consumers" DROP CONSTRAINT IF EXISTS "consumers_type_fkey";

        -- This either. Cannot see it being created anywhere
        -- ALTER TABLE "credentials" DROP CONSTRAINT IF EXISTS "credentials_consumer_type_fkey";

        -- These do not exist on 000_base either...
        -- DROP TABLE IF EXISTS consumer_statuses;
        -- DROP TABLE IF EXISTS consumer_types;
      END
      $$;
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

      assert(connector:query([[
        UPDATE workspaces
        SET config = '{"portal":false}'::json
        WHERE name = 'default'
      ]]))
    end
  },

  cassandra = {
    up = [[ ]],

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

      local default_ws_id, err = connector:query([[
        SELECT id FROM workspaces WHERE name='default';
      ]])
      if err then
        return nil, err
      end

      if not (default_ws_id and default_ws_id[1]) then
        return nil, "failed to fetch default workspace"
      end

      assert(connector:query(fmt([[
        UPDATE workspaces
        SET config = '{"portal":false}'
        WHERE id = %s
      ]], default_ws_id[1].id)))

      -- after the legacy admins are migrated, we don't need this table
      assert(connector:query([[
        DROP TABLE IF EXISTS consumers_rbac_users_map;
      ]]))
    end
  }
}
