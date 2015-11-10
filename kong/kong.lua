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

local config = require "kong.tools.config_loader"
local dao_loader = require "kong.tools.dao_loader"
local utils = require "kong.tools.utils"
local cache = require "kong.tools.database_cache"
local constants = require "kong.constants"
local responses = require "kong.tools.responses"
local ipairs = ipairs
local table_remove = table.remove
local table_insert = table.insert

local loaded_plugins = {}
local core = require("kong.core.handler")

--- Load the configuration for a plugin entry in the DB.
-- Given an API, a Consumer and a plugin name, retrieve the plugin's configuration if it exists.
-- Results are cached in ngx.dict
-- @param[type=string] api_id ID of the API being proxied.
-- @param[type=string] consumer_id ID of the Consumer making the request (if any).
-- @param[type=stirng] plugin_name Name of the plugin being tested for.
-- @treturn table Plugin retrieved from the cache or database.
local function load_plugin_configuration(api_id, consumer_id, plugin_name)
  local cache_key = cache.plugin_key(plugin_name, api_id, consumer_id)

  local plugin = cache.get_or_set(cache_key, function()
    local rows, err = dao.plugins:find_by_keys {
        api_id = api_id,
        consumer_id = consumer_id ~= nil and consumer_id or constants.DATABASE_NULL_ID,
        name = plugin_name
      }
      if err then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end

      if #rows > 0 then
        local plugin_row = table_remove(rows, 1)
        if plugin_row.config == nil then
          plugin_row.config = {}
        end
        return plugin_row
      else
        -- force to insert a cached value (could be avoided)
        return {null = true}
      end
  end)

  if plugin ~= nil and plugin.enabled then
    return plugin
  end
end

--- Detect enabled plugins on the node.
-- Get plugins in the DB (distict by `name`), compare them with plugins in kong.yml's `plugins_available`.
-- If both lists match, return a list of plugins sorted by execution priority for lua-nginx-module's context handlers.
-- @treturn table Array of plugins to execute in context handlers.
local function init_plugins()
  -- TODO: this should be handled with other default configs
  configuration.plugins_available = configuration.plugins_available or {}

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

  local loaded_plugins = {}

  for _, v in ipairs(configuration.plugins_available) do
    local loaded, plugin_handler_mod = utils.load_module_if_exists("kong.plugins."..v..".handler")
    if not loaded then
      error("The following plugin has been enabled in the configuration but it is not installed on the system: "..v)
    else
      ngx.log(ngx.DEBUG, "Loading plugin: "..v)
      table.insert(loaded_plugins, {
        name = v,
        handler = plugin_handler_mod()
      })
    end
  end

  table.sort(loaded_plugins, function(a, b)
    local priority_a = a.handler.PRIORITY or 0
    local priority_b = b.handler.PRIORITY or 0
    return priority_a > priority_b
  end)

  if configuration.send_anonymous_reports then
    table.insert(loaded_plugins, 1, {
      reports = true,
      name = "reports",
      handler = require("kong.reports.handler")()
    })
  end

  return loaded_plugins
end

---
-- @param[type=table] plugins_to_execute
local function plugins_iter(_, i)
  i = i + 1
  local p = ngx.ctx.plugins_for_request[i]
  if p == nil then
    -- End of the iteration
    return
  end

  local plugin, plugin_configuration = p[1], p[2]

  if phase_name == "access" then
    -- Check if any Consumer was authenticated during the access_phase.
    -- If so, retrieve the configuration for this Consumer.
    local consumer_id = ngx.ctx.authenticated_credential and ngx.ctx.authenticated_credential.consumer_id or nil
    if consumer_id ~= nil then
      local consumer_plugin_configuration = load_plugin_configuration(ngx.ctx.api.id, nil, plugin.name)
      if consumer_plugin_configuration ~= nil then
        -- This Consumer has a special configuration when this plugin gets executed.
        -- Override this plugin's configuration for this request.
        plugin_configuration = consumer_plugin_configuration
        ngx.ctx.plugins_for_request[i][2] = consumer_plugin_configuration
      end
    end
  end

  return i, plugin, plugin_configuration.config
end

local function noop()
end

local function plugins_to_execute(loaded_plugins)
  if ngx.ctx.plugins_for_request == nil then
    local t = {}
    -- Build an array of plugins that must be executed for this particular request.
    -- A plugin is considered to be executed if there is a row in the DB which contains:
    -- 1. the API id (contained in ngx.ctx.api.id, retried by the core resolver)
    -- 2. a Consumer id, in which case it overrides any previous plugin found in 1.
    --    this use case will be treated later.
    -- Such a row will contain a `config` value, which is a table.
    for plugin_idx, plugin in ipairs(loaded_plugins) do
      if ngx.ctx.api ~= nil then
        local plugin_configuration = load_plugin_configuration(ngx.ctx.api.id, nil, plugin.name)
        if plugin_configuration ~= nil then
          table_insert(t, {plugin, plugin_configuration})
        end
      end
    end
    ngx.ctx.plugins_for_request = t
  end

  return plugins_iter, nil, 0
end

--- Kong public context handlers.
-- @section kong_handlers

local Kong = {}

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
  -- Loading configuration
  configuration = config.load(os.getenv("KONG_CONF"))
  dao = dao_loader.load(configuration)

  -- Initializing plugins
  loaded_plugins = init_plugins()

  ngx.update_time()
end

-- Calls `init_worker()` on every loaded plugin
function Kong.exec_plugins_init_worker()
  core.init_worker()

  for _, plugin in ipairs(loaded_plugins) do
    plugin.handler:init_worker()
  end
end

function Kong.exec_plugins_certificate()
  core.certificate:before()

  for _, plugin, plugin_conf in plugins_to_execute(loaded_plugins, "certificate") do
    plugin.handler:certificate(plugin_conf)
  end
end

-- Calls `access()` on every loaded plugin
function Kong.exec_plugins_access()
  core.access:before()

  for _, plugin, plugin_conf in plugins_to_execute(loaded_plugins, "access") do
    plugin.handler:access(plugin_conf)
  end

  core.access:after()
end

-- Calls `header_filter()` on every loaded plugin
function Kong.exec_plugins_header_filter()
  core.header_filter:before()

  for _, plugin, plugin_conf in plugins_to_execute(loaded_plugins, "header_filter") do
    plugin.handler:header_filter(plugin_conf)
  end

  core.header_filter:after()
end

-- Calls `body_filter()` on every loaded plugin
function Kong.exec_plugins_body_filter()
  core.body_filter:before()

  for _, plugin, plugin_conf in plugins_to_execute(loaded_plugins, "body_filter") do
    plugin.handler:body_filter(plugin_conf)
  end

  core.body_filter:after()
end

-- Calls `log()` on every loaded plugin
function Kong.exec_plugins_log()
  for _, plugin, plugin_conf in plugins_to_execute(loaded_plugins, "log") do
    plugin.handler:log(plugin_conf)
  end

  core.log()
end

return Kong
