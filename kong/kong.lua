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
local stringy = require "stringy"
local constants = require "kong.constants"
local responses = require "kong.tools.responses"
local ipairs = ipairs
local table_remove = table.remove

local loaded_plugins = {}
local resolver = require("kong.resolver.handler")

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
  for _, plugin_t in ipairs(loaded_plugins) do
    plugin_t.handler:init_worker()
  end
end

function Kong.exec_plugins_certificate()
  resolver.certificate:before()

  for _, plugin_t in ipairs(loaded_plugins) do
    if ngx.ctx.api ~= nil then
      local plugin = load_plugin_configuration(ngx.ctx.api.id, nil, plugin_t.name)
      if not ngx.ctx.stop_phases and plugin then
        plugin_t.handler:certificate(plugin.config)
      end
    end
  end
end

-- Calls `access()` on every loaded plugin
function Kong.exec_plugins_access()
  resolver.access:before()

  for _, plugin_t in ipairs(loaded_plugins) do
    if ngx.ctx.api then
      ngx.ctx.plugins_to_execute[plugin_t.name] = load_plugin_configuration(ngx.ctx.api.id, nil, plugin_t.name)
      local consumer_id = ngx.ctx.authenticated_credential and ngx.ctx.authenticated_credential.consumer_id or nil
      if consumer_id then
        local consumer_plugin = load_plugin_configuration(ngx.ctx.api.id, consumer_id, plugin_t.name)
        if consumer_plugin then
          ngx.ctx.plugins_to_execute[plugin_t.name] = consumer_plugin
        end
      end
    end

    local plugin = ngx.ctx.plugins_to_execute[plugin_t.name]
    if not ngx.ctx.stop_phases and plugin then
      plugin_t.handler:access(plugin.config)
    end
  end

  -- Append any modified querystring parameters
  local parts = stringy.split(ngx.var.backend_url, "?")
  local final_url = parts[1]
  if utils.table_size(ngx.req.get_uri_args()) > 0 then
    final_url = final_url.."?"..ngx.encode_args(ngx.req.get_uri_args())
  end

  ngx.var.backend_url = final_url
  resolver.access:after()
end

-- Calls `header_filter()` on every loaded plugin
function Kong.exec_plugins_header_filter()
  resolver.header_filter:before()

  if not ngx.ctx.stop_phases then
    for _, plugin_t in ipairs(loaded_plugins) do
      local plugin = ngx.ctx.plugins_to_execute[plugin_t.name]
      if plugin then
        plugin_t.handler:header_filter(plugin.config)
      end
    end
  end

  resolver.header_filter:after()
end

-- Calls `body_filter()` on every loaded plugin
function Kong.exec_plugins_body_filter()
  resolver.body_filter:before()

  if not ngx.ctx.stop_phases then
    for _, plugin_t in ipairs(loaded_plugins) do
      local plugin = ngx.ctx.plugins_to_execute[plugin_t.name]
      if plugin then
        plugin_t.handler:body_filter(plugin.config)
      end
    end
  end

  resolver.body_filter:after()
end

-- Calls `log()` on every loaded plugin
function Kong.exec_plugins_log()
  if not ngx.ctx.stop_phases then
    for _, plugin_t in ipairs(loaded_plugins) do
      local plugin = ngx.ctx.plugins_to_execute[plugin_t.name]
      if plugin or plugin_t.reports then
        plugin_t.handler:log(plugin.config)
      end
    end
  end
end

return Kong
