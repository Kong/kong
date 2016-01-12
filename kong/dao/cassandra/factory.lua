-- Kong's cassandra Factory DAO. Entry-point for retrieving DAO objects that allow
-- interactions with the database for entities (APIs, Consumers...).
--
-- Also provides helper methods for preparing queries among the DAOs, migrating the
-- database and dropping it.

local constants = require "kong.constants"
local cassandra = require "cassandra"
local DaoError = require "kong.dao.error"
local stringy = require "stringy"
local Object = require "classic"
local utils = require "kong.tools.utils"

if ngx ~= nil and type(ngx.get_phase) == "function" and ngx.get_phase() == "init" and not ngx.stub then
  cassandra.set_log_level("INFO")
else
  cassandra.set_log_level("QUIET")
end

local CassandraFactory = Object:extend()

-- Shorthand for accessing one of the underlying DAOs
function CassandraFactory:__index(key)
  if key ~= "daos" and self.daos and self.daos[key] then
    return self.daos[key]
  else
    return CassandraFactory[key]
  end
end

-- Instantiate a Cassandra Factory and all its DAOs for various entities
-- @param `properties` Cassandra properties
function CassandraFactory:new(properties, plugins, spawn_cluster)
  self.properties = properties
  self.type = "cassandra"
  self.daos = {}

  if spawn_cluster then
    local ok, err = cassandra.spawn_cluster(self:get_session_options())
    if not ok then
      error(err)
    end
  end

  -- Load core entities DAOs
  for _, entity in ipairs({"apis", "consumers", "plugins"}) do
    self:load_daos(require("kong.dao.cassandra."..entity))
  end

  -- Load plugins DAOs
  if plugins then
    self:load_plugins(plugins)
  end
end

-- Load an array of plugins (array of plugins names). If any of those plugins have DAOs,
-- they will be loaded into the factory.
-- @param plugins Array of plugins names
function CassandraFactory:load_plugins(plugins)
  for _, v in ipairs(plugins) do
    local loaded, plugin_daos_mod = utils.load_module_if_exists("kong.plugins."..v..".daos")
    if loaded then
      if ngx then
        ngx.log(ngx.DEBUG, "Loading DAO for plugin: "..v)
      end
      self:load_daos(plugin_daos_mod)
    elseif ngx then
      ngx.log(ngx.DEBUG, "No DAO loaded for plugin: "..v)
    end
  end
end

-- Load a plugin's DAOs (plugins can have more than one DAO) in the factory and create cascade delete hooks.
-- Cascade delete hooks are triggered when a parent of a foreign row is deleted.
-- @param plugin_daos A table with key/values representing daos names and instances.
function CassandraFactory:load_daos(plugin_daos)
  local dao
  for name, plugin_dao in pairs(plugin_daos) do
    dao = plugin_dao(self.properties)
    dao._factory = self
    self.daos[name] = dao
    if dao._schema then
      -- Check for any foreign relations to trigger cascade deletes
      for field_name, field in pairs(dao._schema.fields) do
        if field.foreign ~= nil then
          -- Foreign key columns need to be queryable, hence they need to have an index
          assert(field.queryable, "Foreign property "..field_name.." of shema "..name.." must be queryable (have an index)")

          local parent_dao_name, parent_column = unpack(stringy.split(field.foreign, ":"))
          assert(parent_dao_name ~= nil, "Foreign property "..field_name.." of schema "..name.." must contain 'parent_dao:parent_column")
          assert(parent_column ~= nil, "Foreign property "..field_name.." of schema "..name.." must contain 'parent_dao:parent_column")

          -- Add delete hook to the parent DAO
          local parent_dao = self[parent_dao_name]
          parent_dao:add_delete_hook(name, field_name, parent_column)
        end
      end
    end
  end
end

function CassandraFactory:drop()
  local err
  for _, dao in pairs(self.daos) do
    err = select(2, dao:drop())
    if err then
      return err
    end
  end
end

function CassandraFactory:get_session_options()
  return {
    shm = "cassandra",
    prepared_shm = "cassandra_prepared",
    contact_points = self.properties.contact_points,
    keyspace = self.properties.keyspace,
    query_options = {
      prepare = true
    },
    username = self.properties.username,
    password = self.properties.password,
    ssl_options = {
      enabled = self.properties.ssl.enabled,
      verify = self.properties.ssl.verify,
      ca = self.properties.ssl.certificate_authority
    }
  }
end

-- Execute a string of queries separated by ;
-- Useful for huge DDL operations such as migrations
-- @param {string} queries Semicolon separated string of queries
-- @param {boolean} no_keyspace Won't set the keyspace if true
-- @return {table} error if any
function CassandraFactory:execute_queries(queries, no_keyspace)
  local options = self:get_session_options()
  options.query_options.same_coordinator = true

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

return CassandraFactory
