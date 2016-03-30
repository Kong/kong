-- Kong, the biggest ape in town
--
--     /\  ____
--     <> ( oo )
--     <>_| ^^ |_
--     <>   @    \
--    /~~\ . . _ |
--   /~~~~\    | |
--  /~~~~~~\/ _| |
--  |[][][]/ / [m]
--  |[][][[m]
--  |[][][]|
--  |[][][]|
--  |[][][]|
--  |[][][]|
--  |[][][]|
--  |[][][]|
--  |[][][]|
--  |[][][]|
--  |[|--|]|
--  |[|  |]|
--  ========
-- ==========
-- |[[    ]]|
-- ==========

local meta = require "kong.meta"

_G._KONG = {
  _NAME = meta._NAME,
  _VERSION = meta._VERSION
}

local core = require "kong.core.handler"
local Serf = require "kong.serf"
local utils = require "kong.tools.utils"
local Events = require "kong.core.events"
local singletons = require "kong.singletons"
local DAOFactory = require "kong.dao.factory"
local conf_loader = require "kong.conf_loader"
local plugins_iterator = require "kong.core.plugins_iterator"

local ipairs = ipairs

local function attach_hooks(events, hooks)
  for k, v in pairs(hooks) do
    events:subscribe(k, v)
  end
end

local function load_plugins(kong_config, events)
  local constants = require "kong.constants"
  local pl_tablex = require "pl.tablex"

  -- short-lived DAO just to retrieve plugins
  local dao = DAOFactory(kong_config)

  local in_db_plugins, sorted_plugins = {}, {}
  local plugins = pl_tablex.merge(constants.PLUGINS_AVAILABLE,
                                  kong_config.custom_plugins, true)

  ngx.log(ngx.DEBUG, "Discovering used plugins")

  local rows, err_t = dao.plugins:find_all()
  if not rows then return nil, tostring(err_t) end

  for _, row in ipairs(rows) do in_db_plugins[row.name] = true end

  -- check all plugins in DB are enabled/installed
  for plugin in pairs(in_db_plugins) do
    if not plugins[plugin] then
      return nil, plugin.." plugin is in use but not enabled"
    end
  end

  -- load installed plugins
  for plugin in pairs(plugins) do
    local ok, handler = utils.load_module_if_exists("kong.plugins."..plugin..".handler")
    if not ok then
      return nil, plugin.." plugin is enabled but not installed"
    end

    local ok, schema = utils.load_module_if_exists("kong.plugins."..plugin..".schema")
    if not ok then
      return nil, "no configuration schema found for plugin: "..plugin
    end

    ngx.log(ngx.DEBUG, "Loading plugin: "..plugin)

    sorted_plugins[#sorted_plugins+1] = {
      name = plugin,
      handler = handler(),
      schema = schema
    }

    -- Attaching hooks
    local ok, hooks = utils.load_module_if_exists("kong.plugins."..plugin..".hooks")
    if ok then
      attach_hooks(events, hooks)
    end
  end

  -- sort plugins by order of execution
  table.sort(sorted_plugins, function(a, b)
    local priority_a = a.handler.PRIORITY or 0
    local priority_b = b.handler.PRIORITY or 0
    return priority_a > priority_b
  end)

  -- add reports plugin if not disabled
  if kong_config.anonymous_reports then
    local reports = require "kong.core.reports"
    reports.enable()
    sorted_plugins[#sorted_plugins+1] = {
      name = "reports",
      handler = reports
    }
  end

  -- sorted for handles, name=true for DAO
  return {sorted = sorted_plugins, names = plugins}
end

-- Kong public context handlers.
-- @section kong_handlers

local Kong = {}

function Kong.init()
  local pl_path = require "pl.path"

  -- retrieve kong_config
  local conf_path = pl_path.join(ngx.config.prefix(), "kong.conf")
  local config = assert(conf_loader(conf_path))

  -- retrieve node plugins
  local events = Events()
  local plugins = assert(load_plugins(config, events))

  -- instanciate long-lived DAO
  local dao = DAOFactory(config, plugins.names, events)

  -- populate singletons
  singletons.loaded_plugins = plugins.sorted
  singletons.serf = Serf.new(config, dao)
  singletons.dao = dao
  singletons.events = events
  singletons.configuration = config

  attach_hooks(events, require "kong.core.hooks")
end

function Kong.init_worker()
  core.init_worker.before()

  singletons.dao:init() -- Executes any initialization by the DB

  for _, plugin in ipairs(singletons.loaded_plugins) do
    plugin.handler:init_worker()
  end
end

function Kong.ssl_certificate()
  core.certificate.before()

  for plugin, plugin_conf in plugins_iterator(singletons.loaded_plugins, true) do
    plugin.handler:certificate(plugin_conf)
  end
end

function Kong.access()
  core.access.before()

  for plugin, plugin_conf in plugins_iterator(singletons.loaded_plugins, true) do
    plugin.handler:access(plugin_conf)
  end

  core.access.after()
end

function Kong.header_filter()
  core.header_filter.before()

  for plugin, plugin_conf in plugins_iterator(singletons.loaded_plugins) do
    plugin.handler:header_filter(plugin_conf)
  end

  core.header_filter.after()
end

function Kong.body_filter()
  for plugin, plugin_conf in plugins_iterator(singletons.loaded_plugins) do
    plugin.handler:body_filter(plugin_conf)
  end

  core.body_filter.after()
end

function Kong.log()
  for plugin, plugin_conf in plugins_iterator(singletons.loaded_plugins) do
    plugin.handler:log(plugin_conf)
  end

  core.log.after()
end

return Kong
