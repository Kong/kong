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

require("kong.core.globalpatches")()

local core = require "kong.core.handler"
local Serf = require "kong.serf"
local utils = require "kong.tools.utils"
local Events = require "kong.core.events"
local singletons = require "kong.singletons"
local DAOFactory = require "kong.dao.factory"
local plugins_iterator = require "kong.core.plugins_iterator"

local ipairs = ipairs

local function attach_hooks(events, hooks)
  for k, v in pairs(hooks) do
    events:subscribe(k, v)
  end
end

local function load_plugins(kong_conf, dao, events)
  local in_db_plugins, sorted_plugins = {}, {}

  ngx.log(ngx.DEBUG, "Discovering used plugins")

  local rows, err_t = dao.plugins:find_all()
  if not rows then return nil, tostring(err_t) end

  for _, row in ipairs(rows) do in_db_plugins[row.name] = true end

  -- check all plugins in DB are enabled/installed
  for plugin in pairs(in_db_plugins) do
    if not kong_conf.plugins[plugin] then
      return nil, plugin.." plugin is in use but not enabled"
    end
  end

  -- load installed plugins
  for plugin in pairs(kong_conf.plugins) do
    local ok, handler = utils.load_module_if_exists("kong.plugins."..plugin..".handler")
    if not ok then
      return nil, plugin.." plugin is enabled but not installed;\n"..handler
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
  if kong_conf.anonymous_reports then
    local reports = require "kong.core.reports"
    reports.toggle(true)
    sorted_plugins[#sorted_plugins+1] = {
      name = "reports",
      handler = reports
    }
  end

  return sorted_plugins
end

-- Kong public context handlers.
-- @section kong_handlers

local Kong = {}

function Kong.init()
  local pl_path = require "pl.path"
  local conf_loader = require "kong.conf_loader"

  -- retrieve kong_config
  local conf_path = pl_path.join(ngx.config.prefix(), "kong.conf")
  local config = assert(conf_loader(conf_path))

  local events = Events() -- retrieve node plugins
  local dao = assert(DAOFactory.new(config, events)) -- instanciate long-lived DAO
  assert(dao:run_migrations()) -- migrating in case embedded in custom nginx

  -- populate singletons
  singletons.loaded_plugins = assert(load_plugins(config, dao, events))
  singletons.serf = Serf.new(config, dao)
  singletons.dao = dao
  singletons.events = events
  singletons.configuration = config

  attach_hooks(events, require "kong.core.hooks")
end

function Kong.init_worker()
  -- special math.randomseed from kong.core.globalpatches
  -- not taking any argument. Must be called only once
  -- and in the init_worker phase, to avoid duplicated
  -- seeds.
  math.randomseed()

  core.init_worker.before()

  local ok, err = singletons.dao:init() -- Executes any initialization by the DB
  if not ok then
    ngx.log(ngx.ERR, err)
  end

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
