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

local core = require "kong.core.handler"
local singletons = require "kong.singletons"
local utils = require "kong.tools.utils"
local dao_loader = require "kong.tools.dao_loader"
local config_loader = require "kong.tools.config_loader"
local plugins_iterator = require "kong.core.plugins_iterator"
local Events = require "kong.core.events"

local ipairs = ipairs
local table_insert = table.insert
local table_sort = table.sort

--- Attach a hooks table to the event bus
local function attach_hooks(events, hooks)
  for k, v in pairs(hooks) do
    events:subscribe(k, v)
  end
end

--- Load enabled plugins on the node.
-- Get plugins in the DB (distinct by `name`), compare them with plugins
-- in `configuration.plugins`. If both lists match, return a list
-- of plugins sorted by execution priority for lua-nginx-module's context handlers.
-- @treturn table Array of plugins to execute in context handlers.
local function load_node_plugins(configuration)
  ngx.log(ngx.DEBUG, "Discovering used plugins")
  local db_plugins, err = singletons.dao.plugins:find_distinct()
  if err then
    error(err)
  end

  -- Checking that the plugins in the DB are also enabled
  for _, v in ipairs(db_plugins) do
    if not utils.table_contains(configuration.plugins, v) then
      error("You are using a plugin that has not been enabled in the configuration: "..v)
    end
  end

  local sorted_plugins = {}

  for _, v in ipairs(configuration.plugins) do
    local loaded, plugin_handler_mod = utils.load_module_if_exists("kong.plugins."..v..".handler")
    if not loaded then
      error("The following plugin has been enabled in the configuration but it is not installed on the system: "..v)
    else
      ngx.log(ngx.DEBUG, "Loading plugin: "..v)
      table_insert(sorted_plugins, {
        name = v,
        handler = plugin_handler_mod()
      })
    end

    -- Attaching hooks
    local loaded, plugin_hooks = utils.load_module_if_exists("kong.plugins."..v..".hooks")
    if loaded then
      attach_hooks(singletons.events, plugin_hooks)
    end
  end

  table_sort(sorted_plugins, function(a, b)
    local priority_a = a.handler.PRIORITY or 0
    local priority_b = b.handler.PRIORITY or 0
    return priority_a > priority_b
  end)

  if configuration.send_anonymous_reports then
    table_insert(sorted_plugins, 1, {
      name = "reports",
      handler = require("kong.core.reports")
    })
  end

  return sorted_plugins
end

--- Kong public context handlers.
-- @section kong_handlers

local Kong = {}

local function prepare_module_variables()
  singletons.configuration   = singletons.configuration   or config_loader.load(os.getenv("KONG_CONF"))
  singletons.events          = singletons.events          or Events()
  singletons.dao             = singletons.dao             or dao_loader.load(singletons.configuration, true, singletons.events)
  singletons.loaded_plugins  = singletons.loaded_plugins  or load_node_plugins(singletons.configuration)
end

--- Init Kong's environment in the Nginx master process.
-- To be called by the lua-nginx-module `init_by_lua` directive.
-- Execution:
--   - load the configuration from the path computed by the CLI
--   - instanciate the DAO Factory
--   - load the used plugins
--     - load all plugins if used and installed
--     - sort the plugins by priority
--
-- If any error happens during the initialization of the DAO or plugins,
-- it return an nginx error and exit.
function Kong.init()
  local status, err = pcall(function() 
      prepare_module_variables()

      -- Attach core hooks
      attach_hooks(singletons.events, require("kong.core.hooks"))

      if singletons.configuration.send_anonymous_reports then
        -- Generate the unique_str inside the module
        local reports = require "kong.core.reports"
        reports.enable()
      end

      ngx.update_time()
    end)
  if not status then
    ngx.log(ngx.ERR, "Startup error: "..err)
    os.exit(1)
  end
end

function Kong.init_worker()
  prepare_module_variables()

  core.init_worker.before()

  for _, plugin in ipairs(singletons.loaded_plugins) do
    plugin.handler:init_worker()
  end
end

function Kong.ssl_certificate()
  core.certificate.before()

  for plugin, plugin_conf in plugins_iterator(singletons.loaded_plugins, "certificate") do
    plugin.handler:certificate(plugin_conf)
  end
end

function Kong.access()
  core.access.before()

  for plugin, plugin_conf in plugins_iterator(singletons.loaded_plugins, "access") do
    plugin.handler:access(plugin_conf)
  end

  core.access.after()
end

function Kong.header_filter()
  core.header_filter.before()

  for plugin, plugin_conf in plugins_iterator(singletons.loaded_plugins, "header_filter") do
    plugin.handler:header_filter(plugin_conf)
  end

  core.header_filter.after()
end

function Kong.body_filter()
  for plugin, plugin_conf in plugins_iterator(singletons.loaded_plugins, "body_filter") do
    plugin.handler:body_filter(plugin_conf)
  end

  core.body_filter.after()
end

function Kong.log()
  for plugin, plugin_conf in plugins_iterator(singletons.loaded_plugins, "log") do
    plugin.handler:log(plugin_conf)
  end

  core.log.after()
end

return Kong