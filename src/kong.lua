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

utils = require "kong.tools.utils"
local cache = require "kong.tools.cache"
local constants = require "kong.constants"
local timestamp = require "kong.tools.timestamp"

-- Define the plugins to load here, in the appropriate order
local plugins = {}

local _M = {}

local function load_plugin_conf(api_id, application_id, plugin_name)
  local cache_key = cache.plugin_key(plugin_name, api_id, application_id)

  local plugin = cache.get_and_set(cache_key, function()
    local rows, err = dao.plugins:find_by_keys {
        api_id = api_id,
        application_id = application_id ~= nil and application_id or constants.DATABASE_NULL_ID,
        name = plugin_name
      }
      if err then
        ngx.log(ngx.ERR, err)
        utils.show_error(500)
      end

      if #rows > 0 then
        return table.remove(rows, 1)
      else
        return { null = true }
      end
  end)

  if plugin and not plugin.null and plugin.enabled then
    return plugin
  else
    return nil
  end
end

local function init_plugins()
  plugins_available = configuration.plugins_available and configuration.plugins_available or {}

  print("Discovering used plugins. Please wait..")
  local db_plugins, err = dao.plugins:find_distinct()
  if err then
    error(err)
  end

  -- Checking that the plugins in the DB are also enabled
  for _, v in ipairs(db_plugins) do
    if not utils.array_contains(plugins_available, v) then
      error("You are using a plugin that has not been enabled in the configuration: "..v)
    end
  end

  local unsorted_plugins = {} -- It's a multivalue table: k1 = {v1, v2, v3}, k2 = {...}

  for _, v in ipairs(plugins_available) do
    local status, res = pcall(require, "kong.plugins."..v..".handler")
    if not status then
      error("The following plugin has been enabled in the configuration but is not installed on the system: "..v)
    else
      print("Loading plugin: "..v)
      local plugin_handler = res()
      local priority = plugin_handler.PRIORITY and plugin_handler.PRIORITY or 0

      -- Add plugin to the right priority
      local list = unsorted_plugins[priority]
      if not list then list = {} end -- The list is required in case more plugins share the same priority level
      table.insert(list, {
        name = v,
        handler = plugin_handler
      })
      unsorted_plugins[priority] = list
    end
  end

  local result = {}

  -- Now construct the final ordered plugin list
  -- resolver is always the first plugin as it is the one retrieving any needed information
  table.insert(result, {
    resolver = true,
    name = "resolver",
    handler = require("kong.resolver.handler")()
  })

  -- Add the plugins in a sorted order
  for _, v in utils.sort_table_iter(unsorted_plugins, utils.sort.descending) do -- In descending order
    if v then
      for _, p in ipairs(v) do
        table.insert(result, p)
      end
    end
  end

  return result
end

-- To be called by nginx's init_by_lua directive.
-- Execution:
--   - load the configuration from the apth computed by the CLI
--   - instanciate the DAO
--     - prepare the statements
--   - load the used plugins
--     - load all plugins if used and installed
--     - load the resolver
--     - sort the plugins by priority
--
-- If any error during the initialization of the DAO or plugins, it will be thrown and needs to be catched in init_by_lua.
-- @return nil
function _M.init()
  -- Loading configuration
  configuration, dao = utils.load_configuration_and_dao(os.getenv("KONG_CONF"))

  -- Initializing DAO
  local err = dao:prepare()
  if err then
    error("cannot prepare statements: "..err)
  end

  -- Initializing plugins
  plugins = init_plugins()
end

-- Calls plugins_access() on every loaded plugin
-- @return nil
function _M.exec_plugins_access()
  -- Setting a property that will be available for every plugin
  ngx.ctx.started_at = timestamp.get_utc()
  ngx.ctx.plugin_conf = {}

  -- Iterate over all the plugins
  for _, plugin in ipairs(plugins) do
    if ngx.ctx.api then
      ngx.ctx.plugin_conf[plugin.name] = load_plugin_conf(ngx.ctx.api.id, nil, plugin.name)
      local application_id = ngx.ctx.authenticated_entity and ngx.ctx.authenticated_entity.id or nil
      if application_id then
        local app_plugin_conf = load_plugin_conf(ngx.ctx.api.id, application_id, plugin.name)
        if app_plugin_conf then
          ngx.ctx.plugin_conf[plugin.name] = app_plugin_conf
        end
      end
    end

    local conf = ngx.ctx.plugin_conf[plugin.name]
    if not ngx.ctx.error and (plugin.resolver or conf) then
      plugin.handler:access(conf and conf.value or nil)
    end
  end

  ngx.ctx.proxy_started_at = timestamp.get_utc() -- Setting a property that will be available for every plugin
end

-- Calls header_filter() on every loaded plugin
-- @return nil
function _M.exec_plugins_header_filter()
  ngx.ctx.proxy_ended_at = timestamp.get_utc() -- Setting a property that will be available for every plugin

  if not ngx.ctx.error then
    for _, plugin in ipairs(plugins) do
      local conf = ngx.ctx.plugin_conf[plugin.name]
      if conf then
        plugin.handler:header_filter(conf.value)
      end
    end
  end
end

-- Calls body_filter() on every loaded plugin
-- @return nil
function _M.exec_plugins_body_filter()
  if not ngx.ctx.error then
    for _, plugin in ipairs(plugins) do
      local conf = ngx.ctx.plugin_conf[plugin.name]
      if conf then
        plugin.handler:body_filter(conf.value)
      end
    end
  end
end

-- Calls log() on every loaded plugin
-- @return nil
function _M.exec_plugins_log()
  if not ngx.ctx.error then

    -- Creating the log variable that will be serialized
    local message = {
      request = {
        headers = ngx.req.get_headers(),
        size = ngx.var.request_length
      },
      response = {
        headers = ngx.resp.get_headers(),
        size = ngx.var.body_bytes_sent
      },
      authenticated_entity = ngx.ctx.authenticated_entity,
      api = ngx.ctx.api,
      ip = ngx.var.remote_addr,
      status = ngx.status,
      url = ngx.var.uri,
      started_at = ngx.ctx.started_at
    }

    ngx.ctx.log_message = message
    for _, plugin in ipairs(plugins) do
      local conf = ngx.ctx.plugin_conf[plugin.name]
      if conf then
        plugin.handler:log(conf.value)
      end
    end
  end
end

return _M
