local inspect = require "inspect"

local BaseDB = require "kong.dao.base_db"
local utils = require "kong.tools.utils"
local cassandra = require "cassandra"

cassandra.set_log_level("QUIET")

local CassandraDB = BaseDB:extend()

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

function CassandraDB:insert(table_name, tbl)
  local values_buf = {}
  for col in pairs(tbl) do
    values_buf[#values_buf + 1] = "?"
  end

  local query = string.format("INSERT INTO %s(%s) VALUES(%s)",
                              table_name,
                              self:_get_columns(tbl),
                              table.concat(values_buf, ", "))
  local err = select(2, self:query(query, tbl))
  if err then
    return nil, err
  end

  return tbl
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
