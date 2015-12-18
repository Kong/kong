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
local utils = require "kong.tools.utils"
local dao_loader = require "kong.tools.dao_loader"
local config_loader = require "kong.tools.config_loader"
local plugins_iterator = require "kong.core.plugins_iterator"

local ipairs = ipairs
local table_insert = table.insert
local table_sort = table.sort

local loaded_plugins = {}
-- @TODO make those locals too
-- local configuration
-- local dao_factory

--- Load enabled plugins on the node.
-- Get plugins in the DB (distinct by `name`), compare them with plugins
-- in kong.yml's `plugins_available`. If both lists match, return a list
-- of plugins sorted by execution priority for lua-nginx-module's context handlers.
-- @treturn table Array of plugins to execute in context handlers.
local function load_node_plugins(configuration)
  ngx.log(ngx.DEBUG, "Discovering used plugins")
  local db_plugins, err = dao.plugins:find_distinct()
  if err then
    error(err)
  end

  -- Checking that the plugins in the DB are also enabled
  for _, v in ipairs(db_plugins) do
    if not utils.table_contains(configuration.plugins_available, v) then
      error("You are using a plugin that has not been enabled in the configuration: "..v)
    end
  end

  local sorted_plugins = {}

  for _, v in ipairs(configuration.plugins_available) do
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
-- it will be thrown and needs to be catched in `init_by_lua`.
function Kong.init()
  configuration = config_loader.load(os.getenv("KONG_CONF"))
  dao = dao_loader.load(configuration, true)
  loaded_plugins = load_node_plugins(configuration)
  process_id = utils.random_string()
  ngx.update_time()
end

function Kong.exec_plugins_init_worker()
  core.init_worker()

  for _, plugin in ipairs(loaded_plugins) do
    plugin.handler:init_worker()
  end
end

function Kong.exec_plugins_certificate()
  core.certificate()

  for plugin, plugin_conf in plugins_iterator(loaded_plugins, "certificate") do
    plugin.handler:certificate(plugin_conf)
  end
end

function Kong.exec_plugins_access()
  core.access.before()

  for plugin, plugin_conf in plugins_iterator(loaded_plugins, "access") do
    plugin.handler:access(plugin_conf)
  end

  core.access.after()
end

function Kong.exec_plugins_header_filter()
  core.header_filter.before()

  for plugin, plugin_conf in plugins_iterator(loaded_plugins, "header_filter") do
    plugin.handler:header_filter(plugin_conf)
  end

  core.header_filter.after()
end

function Kong.exec_plugins_body_filter()
  for plugin, plugin_conf in plugins_iterator(loaded_plugins, "body_filter") do
    plugin.handler:body_filter(plugin_conf)
  end

  core.body_filter.after()
end

function Kong.exec_plugins_log()
  for plugin, plugin_conf in plugins_iterator(loaded_plugins, "log") do
    plugin.handler:log(plugin_conf)
  end

  core.log()
end

return Kong
