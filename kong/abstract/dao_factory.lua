local Object = require "classic"
local utils = require "kong.tools.utils"

local function log(msg)
  if ngx ~= nil then
    ngx.log(ngx.DEBUG, msg)
  end
end

local AbstractDAOFactory = Object:extend()

-- Shorthand for accessing one of the underlying DAOs
function AbstractDAOFactory:__index(key)
  if key ~= "daos" and self.daos and self.daos[key] then
    return self.daos[key]
  else
    return AbstractDAOFactory[key]
  end
end

--- Instanciate a DAO Factory.
-- Should be called by subclasses on instanciation.
function AbstractDAOFactory:new(db_name, properties, session_options, plugins, events_handler)
  assert(type(properties) == "table", "arg #1 must be a table")

  self.type = db_name
  self.properties = properties
  self.session_options = session_options
  self.events_handler = events_handler
  self.daos = {}

  -- The BaseDAO class for this DB
  local BaseDAO = require("kong.dao."..db_name..".base_dao")

  self:attach_core_entities_daos(BaseDAO)

  if plugins ~= nil then
    self:attach_plugins_daos(plugins)
  end
end

function AbstractDAOFactory:get_session_options()
  return utils.shallow_copy(self.session_options)
end

local CORE_ENTITIES = {"apis", "consumers", "plugins", "nodes"}

--- Retrieve core entities DAOs to attach to this factory.
--
function AbstractDAOFactory:attach_core_entities_daos(BaseDAO)
  for _, v in ipairs(CORE_ENTITIES) do
    -- This is a subclass of the BaseDAO, probably with DB-specific methods.
    local ok, core_dao = utils.load_module_if_exists("kong.dao."..self.type.."."..v)
    if ok then
      self:attach_daos(core_dao)
    else
      -- Nothing particular with this DAO, its just an instance of the BaseDAO.
      local schema = require("kong.dao.schemas."..v)
      self:attach_daos({[v] = BaseDAO}, v, schema)
    end
  end
end

--- Retrieve plugins entities DAOs to attach to this factory.
--
function AbstractDAOFactory:attach_plugins_daos(plugins)
  for _, v in ipairs(plugins) do
    local ok, plugin_daos = utils.load_module_if_exists("kong.plugins."..v..".daos")
    if ok then
      self:attach_daos(plugin_daos)
      log("DAO loaded for plugin: "..v)
    else
      log("No DAO loaded for plugin: "..v)
    end
  end
end

--- Attach DAOs to this factory.
-- Receives a table where key is name of DAO, value is class of this DAO.
-- The class of a DAO could be BaseDAO (aka. db-specific DAO), or a subclass of BaseDAO.
-- A subclass of BaseDAO means this entity does particular things, for ex: `apis:find_all()`.
function AbstractDAOFactory:attach_daos(daos, table, schema)
  for name, DAOClass in pairs(daos) do
    if schema ~= nil and table ~= nil then
      -- Instanciating a BaseDAO
      self.daos[name] = DAOClass(table, schema, self.session_options, self.events_handler)
    else
      -- Instanciating a subclass of BaseDAO
      self.daos[name] = DAOClass(self.session_options, self.events_handler)
    end
  end
end

function AbstractDAOFactory:drop()
  for _, dao in pairs(self.daos) do
    local err = select(2, dao:drop())
    if err then
      return err
    end
  end
end

return AbstractDAOFactory
