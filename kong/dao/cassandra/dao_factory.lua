-- Kong's cassandra Factory DAO. Entry-point for retrieving DAO objects that allow
-- interactions with the database for entities (APIs, Consumers...).
--
-- Also provides helper methods for preparing queries among the DAOs, migrating the
-- database and dropping it.

local AbstractDAOFactory = require "kong.abstract.dao_factory"
local constants = require "kong.constants"
local cassandra = require "cassandra"
local types = require "cassandra.types"
local DaoError = require "kong.dao.error"
local stringy = require "stringy"

local CassandraDAOFactory = AbstractDAOFactory:extend()

-- Shorthand for accessing one of the underlying DAOs
function CassandraDAOFactory:__index(key)
  if key ~= "daos" and self.daos and self.daos[key] then
    return self.daos[key]
  else
    return CassandraDAOFactory[key]
  end
end

-- Instantiate a Cassandra Factory and all its DAOs for various entities
-- @param `properties` Cassandra properties
function CassandraDAOFactory:new(properties, plugins, events_handler, spawn_cluster)
  local session_options = {
    shm = "cassandra",
    prepared_shm = "cassandra_prepared",
    contact_points = properties.contact_points,
    keyspace = properties.keyspace,
    query_options = {
      prepare = true
    },
    username = properties.username,
    password = properties.password,
    ssl_options = {
      enabled = properties.ssl.enabled,
      verify = properties.ssl.verify,
      ca = properties.ssl.certificate_authority
    }
  }

  CassandraDAOFactory.super.new(self, "cassandra", properties, session_options, plugins, events_handler)

  if properties.username and properties.password then
    self.properties.auth = cassandra.auth.PlainTextProvider(properties.username, properties.password)
  end

  if ngx ~= nil and ngx.get_phase() == "init" then
    local ok, err = cassandra.spawn_cluster(self:get_session_options())
    if not ok then
      error(err)
    end
  end
end

function CassandraDAOFactory:attach_core_entities_daos(...)
  CassandraDAOFactory.super.attach_core_entities_daos(self, ...)
  self:ugly_hack()
end

function CassandraDAOFactory:attach_plugins_daos(...)
  CassandraDAOFactory.super.attach_plugins_daos(self, ...)
  self:ugly_hack()
end

function CassandraDAOFactory:ugly_hack()
  for dao_name, dao in pairs(self.daos) do
    self.daos[dao_name].factory = self
    if dao.schema then
      -- Check for any foreign relations to trigger cascade deletes
      for field_name, field in pairs(dao.schema.fields) do
        if field.foreign ~= nil then
          -- Foreign key columns need to be queryable, hence they need to have an index
          assert(field.queryable, "Foreign property "..field_name.." of schema "..dao_name.." must be queryable (have an index)")

          local parent_dao_name, parent_column = unpack(stringy.split(field.foreign, ":"))
          assert(parent_dao_name ~= nil, "Foreign property "..field_name.." of schema "..dao_name.." must contain 'parent_dao:parent_column'")
          assert(parent_column ~= nil, "Foreign property "..field_name.." of schema "..dao_name.." must contain 'parent_dao:parent_column'")

          -- Add delete hook to the parent DAO
          local parent_dao = self.daos[parent_dao_name]
          parent_dao:add_delete_hook(dao_name, field_name, parent_column)
        end
      end
    end
  end
end

function CassandraDAOFactory:drop()
  local err
  for _, dao in pairs(self.daos) do
    err = select(2, dao:drop())
    if err then
      return err
    end
  end
end

function CassandraDAOFactory:get_session_options()
  return {
    shm = "cassandra",
    prepared_shm = "cassandra_prepared",
    contact_points = self.properties.contact_points,
    keyspace = self.properties.keyspace,
    query_options = {
      prepare = true,
      consistency = types.consistencies[self.properties.consistency:lower()]
    },
    socket_options = {
      connect_timeout = self.properties.timeout,
      read_timeout = self.properties.timeout
    },
    ssl_options = {
      enabled = self.properties.ssl.enabled,
      verify = self.properties.ssl.verify,
      ca = self.properties.ssl.certificate_authority
    },
    auth = self.properties.auth
  }
end

-- Execute a string of queries separated by ;
-- Useful for huge DDL operations such as migrations
-- @param {string} queries Semicolon separated string of queries
-- @param {boolean} no_keyspace Won't set the keyspace if true
-- @return {table} error if any
function CassandraDAOFactory:execute_queries(queries, no_keyspace)
  local options = self:get_session_options()
  options.query_options.prepare = false

  if no_keyspace then
    options.keyspace = nil
  end

  local session, err = cassandra.spawn_session(options)
  if not session then
    return DaoError(err, constants.DATABASE_ERROR_TYPES.DATABASE)
  end

  -- Cassandra only supports BATCH on DML statements.
  -- We must split commands to execute them individually for migrations and such
  queries = stringy.split(queries, ";")
  for _, query in ipairs(queries) do
    if stringy.strip(query) ~= "" then
      err = select(2, session:execute(query))
      if err then
        break
      end
    end
  end

  session:shutdown()

  if err then
    return DaoError(err, constants.DATABASE_ERROR_TYPES.DATABASE)
  end
end

return CassandraDAOFactory
