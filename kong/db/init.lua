local DAO          = require "kong.db.dao"
local Entity       = require "kong.db.schema.entity"
local Errors       = require "kong.db.errors"
local Strategies   = require "kong.db.strategies"
local MetaSchema   = require "kong.db.schema.metaschema"


local fmt          = string.format
local type         = type
local pairs        = pairs
local error        = error
local ipairs       = ipairs
local rawget       = rawget
local setmetatable = setmetatable


-- maybe a temporary constant table -- could be move closer
-- to schemas and entities since schemas will also be used
-- independently from the DB module (Admin API for GUI)
local CORE_ENTITIES = {
  "services",
  "routes",
}


local DB = {}
DB.__index = function(self, k)
  return DB[k] or rawget(self, "daos")[k]
end


function DB.new(kong_config, strategy)
  if not kong_config then
    error("missing kong_config", 2)
  end

  if strategy ~= nil and type(strategy) ~= "string" then
    error("strategy must be a string", 2)
  end

  local schemas = {}

  do
    -- load schemas
    -- core entities are for now the only source of schemas.
    -- TODO: support schemas from plugins entities as well.

    for _, entity_name in ipairs(CORE_ENTITIES) do
      local entity_schema = require("kong.db.schema.entities." .. entity_name)

      -- validate core entities schema via metaschema
      local ok, err = MetaSchema:validate(entity_schema)
      if not ok then
        return nil, fmt("schema of entity '%s' is invalid: %s", entity_name,
                        err)
      end

      schemas[entity_name] = Entity.new(entity_schema)
    end
  end

  -- load errors

  local errors = Errors.new(strategy)

  -- load strategy

  local connector, strategies, err = Strategies.new(kong_config, strategy,
                                                    schemas, errors)
  if err then
    return nil, err
  end

  local daos = {}

  do
    -- load DAOs

    for _, schema in pairs(schemas) do
      local strategy = strategies[schema.name]
      if not strategy then
        return nil, fmt("no strategy found for schema '%s'", schema.name)
      end

      daos[schema.name] = DAO.new(schema, strategy, errors)
    end
  end

  -- we are 200 OK

  local self   = {
    daos       = daos,       -- each of those has the connector singleton
    strategies = strategies,
    connector  = connector,
  }

  return setmetatable(self, DB)
end


function DB:init_connector()
  -- I/O with the DB connector singleton
  -- Implementation up to the strategy's connector. A place for:
  --   - connection check
  --   - cluster retrievel (cassandra)
  --   - prepare statements
  --   - nop (default)

  return self.connector:init()
end


function DB:connect()
  return self.connector:connect()
end


function DB:setkeepalive()
  return self.connector:setkeepalive()
end


function DB:reset()
  return self.connector:reset()
end


function DB:truncate()
  return self.connector:truncate()
end


function DB:set_events_handler(events)
  for _, dao in pairs(self.daos) do
    dao.events = events
  end
end


return DB
