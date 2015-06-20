-- Kong's cassandra Factory DAO. Entry-point for retrieving DAO objects that allow
-- interations with the database for entities (APIs, Consumers...).
--
-- Also provides helper methods for preparing queries among the DAOs, migrating the
-- database and dropping it.

local constants = require "kong.constants"
local cassandra = require "cassandra"
local DaoError = require "kong.dao.error"
local stringy = require "stringy"
local Object = require "classic"
local utils = require "kong.tools.utils"

local CassandraFactory = Object:extend()

-- Shorthand for accessing one of the underlying DAOs
function CassandraFactory:__index(key)
  if key ~= "daos" and self.daos and self.daos[key] then
    return self.daos[key]
  else
    return CassandraFactory[key]
  end
end

-- Instanciate a Cassandra Factory and all its DAOs for various entities
-- @param `properties` Cassandra properties
function CassandraFactory:new(properties, plugins)
  self._properties = properties
  self.type = "cassandra"
  self.daos = {}

  -- Load core entities DAOs
  for _, entity in ipairs({"apis", "consumers", "plugins_configurations"}) do
    self:load_daos(require("kong.dao.cassandra."..entity))
  end

  -- Load plugins DAOs
  if plugins then
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
end

function CassandraFactory:load_daos(plugin_daos)
  for name, plugin_dao in pairs(plugin_daos) do
    self.daos[name] = plugin_dao(self._properties)
    self.daos[name]._factory = self
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

-- Prepare all statements of collections `queries` property and put them
-- in a statements cache
--
-- Note:
-- Even if the BaseDAO's :_execute_kong_query() method support preparation of statements on-the-go,
-- this method should be called when Kong starts in order to detect any failure in advance
-- as well as test the connection to Cassandra.
--
-- @return error if any
function CassandraFactory:prepare()
  local function prepare_collection(collection, collection_queries)
    local err
    for stmt_name, collection_query in pairs(collection_queries) do
      err = select(2, collection:prepare(collection_query))
      if err then
        error(err)
      end
    end
  end

  for _, collection in pairs(self.daos) do
    if collection.queries then
      local status, err = pcall(function() prepare_collection(collection, collection.queries) end)
      if not status then
        return err
      end
    end
  end
end

-- Execute a string of queries separated by ;
-- Useful for huge DDL operations such as migrations
-- @param {string} queries Semicolon separated string of queries
-- @param {boolean} no_keyspace Won't set the keyspace if true
-- @return {string} error if any
function CassandraFactory:execute_queries(queries, no_keyspace)
  local ok, err
  local session = cassandra.new()
  session:set_timeout(self._properties.timeout)

  ok, err = session:connect(self._properties.hosts, self._properties.port)
  if not ok then
    return DaoError(err, constants.DATABASE_ERROR_TYPES.DATABASE)
  end

  if no_keyspace == nil then
    ok, err = session:set_keyspace(self._properties.keyspace)
    if not ok then
      return DaoError(err, constants.DATABASE_ERROR_TYPES.DATABASE)
    end
  end

  -- Cassandra only supports BATCH on DML statements.
  -- We must split commands to execute them individually for migrations and such
  queries = stringy.split(queries, ";")
  for _, query in ipairs(queries) do
    if stringy.strip(query) ~= "" then
      local _, stmt_err = session:execute(query)
      if stmt_err then
        return DaoError(stmt_err, constants.DATABASE_ERROR_TYPES.DATABASE)
      end
    end
  end

  session:close()
end

return CassandraFactory
