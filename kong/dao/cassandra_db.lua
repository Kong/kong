local inspect = require "inspect"

local timestamp = require "kong.tools.timestamp"
local BaseDB = require "kong.dao.base_db"
local utils = require "kong.tools.utils"
local uuid = require "lua_uuid"

local ngx_stub = _G.ngx
_G.ngx = nil
local cassandra = require "cassandra"
_G.ngx = ngx_stub

local CassandraDB = BaseDB:extend()

CassandraDB.dao_insert_values = {
  id = function()
    return uuid()
  end,
  timestamp = function()
    return timestamp.get_utc()
  end
}

function CassandraDB:new(options)
  local conn_opts = {
    shm = "cassandra",
    prepared_shm = "cassandra_prepared",
    contact_points = options.contact_points,
    keyspace = options.keyspace,
    query_options = {
      prepare = true
    },
    username = options.username,
    password = options.password,
    ssl_options = {
      enabled = options.ssl.enabled,
      verify = options.ssl.verify,
      ca = options.ssl.certificate_authority
    }
  }

  CassandraDB.super.new(self, "cassandra", conn_opts)
end

function CassandraDB:init_db()

end

-- Formatting

function CassandraDB:_get_args(model)
  local fields = model.__schema.fields
  local cols, bind_args, args = {}, {}, {}

  for col, field in pairs(fields) do
    -- cassandra serializers
    local value = model[col]
    if value == nil then
      value = cassandra.unset
    elseif field.type == "id" then
      value = cassandra.uuid(value)
    elseif field.type == "timestamp" then
      value = cassandra.timestamp(value)
    end

    cols[#cols + 1] = col
    args[#args + 1] = value
    bind_args[#bind_args + 1] = "?"
  end

  return table.concat(cols, ", "), table.concat(bind_args, ", "), args
end

function CassandraDB:query(query, args)
  CassandraDB.super.query(self, query, args)

  local conn_opts = self:_get_conn_options()
  local session, err = cassandra.spawn_session(conn_opts)
  if err then
    return nil, tostring(err)
  end

  local res, err = session:execute(query, args)
  session:set_keep_alive()
  if err then
    return nil, tostring(err)
  end

  return res
end

function CassandraDB:insert(model)
  local cols, binds, args = self:_get_args(model)
  local query = string.format("INSERT INTO %s(%s) VALUES(%s)",
                              model.__table, cols, binds)
  local err = select(2, self:query(query, args))
  if err then
    return nil, err
  end

  return model
end

-- Migrations

function CassandraDB:queries(queries)
  for _, query in ipairs(utils.split(queries, ";")) do
    if utils.strip(query) ~= "" then
      local err = select(2, self:query(query))
      if err then
        return err
      end
    end
  end
end

function CassandraDB:drop_table(table_name)
  return select(2, self:query("DROP TABLE "..table_name))
end

function CassandraDB:current_migrations()
  -- Check if schema_migrations table exists first
  local rows, err = self:query([[
    SELECT COUNT(*) FROM system.schema_columnfamilies
    WHERE keyspace_name = ? AND columnfamily_name = ?
  ]], {
    self.options.keyspace,
    "schema_migrations"
  })
  if err then
    return nil, err
  end

  if rows[1].count > 0 then
    return self:query "SELECT * FROM schema_migrations"
  else
    return {}
  end
end

function CassandraDB:record_migration(id, name)
  return select(2, self:query([[
    UPDATE schema_migrations SET migrations = migrations + ? WHERE id = ?
  ]], {
    cassandra.list {name},
    id
  }))
end

return CassandraDB
