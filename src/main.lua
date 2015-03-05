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
local constants = require "kong.constants"

-- Define the plugins to load here, in the appropriate order
local plugins = {}

local _M = {}

local function load_plugin_conf(api_id, application_id, plugin_name)
  local cache_key = utils.cache_plugin_key(plugin_name, api_id, application_id)

  local plugin = utils.cache_get_and_set(cache_key, function()
    local rows, err = dao.plugins:find_by_keys {
        api_id = api_id,
        application_id = application_id ~= nil and application_id or constants.DATABASE_NULL_ID,
        name = plugin_name
      }
      if err then
        ngx.log(ngx.ERR, err.message)
        utils.show_error(500)
      end

      if #rows > 0 then
        return table.remove(rows, 1)
      else
        return {null=true}
      end
  end)

  if plugin and not plugin.null and plugin.enabled then
    return plugin
  else
    return nil
  end
end

local function init_plugins()
  -- Initializing plugins

  installed_plugins = configuration.plugins_enabled and configuration.plugins_enabled or {}

  print("Discovering used plugins. Please wait..")
  local db_plugins, err = dao.plugins:find_distinct()
  if err then
    error(err)
  end

  -- Checking that the plugins in the DB are also enabled
  for _,v in ipairs(db_plugins) do
    if not utils.array_contains(installed_plugins, v) then
      error("You are using a plugin that has not been enabled in the configuration: "..v)
    end
  end

  local unsorted_plugins = {} -- It's a multivalue table: k1 = {v1, v2, v3}, k2 = {...}

  for _, v in ipairs(installed_plugins) do
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

  -- Now construct the final ordered plugin list, core is always the first plugin
  table.insert(result, {
    core = true,
    name = "core",
    handler = require("kong.core.handler")()
  })

  -- Add the plugins in a sorted order
  for _, v in utils.sort_table(unsorted_plugins, utils.sort.descending) do -- In descending order
    if v then
      for _, p in ipairs(v) do
        table.insert(result, p)
      end
    end
  end

  return result
end

function _M.init()
  -- Loading configuration
  configuration, dao = utils.load_configuration_and_dao(os.getenv("KONG_CONF"))

  -- Initializing DAO
  local err = dao:prepare()
  if err then
    error("Cannot prepare Cassandra statements: "..err.message)
  end

  -- Initializing plugins
  plugins = init_plugins()
end

function _M.access()
  -- Setting a property that will be available for every plugin
  ngx.ctx.start = ngx.now()
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
    if not ngx.ctx.error and (plugin.core or conf) then
      plugin.handler:access(conf and conf.value or nil)
    end
  end

  ngx.ctx.proxy_start = ngx.now() -- Setting a property that will be available for every plugin
end

function _M.header_filter()
  ngx.ctx.proxy_end = ngx.now() -- Setting a property that will be available for every plugin

  if not ngx.ctx.error then
    for _, plugin in ipairs(plugins) do
      local conf = ngx.ctx.plugin_conf[plugin.name]
      if conf then
        plugin.handler:header_filter(conf.value)
      end
    end
  end
end

function _M.body_filter()
  if not ngx.ctx.error then
    for _, plugin in ipairs(plugins) do
      local conf = ngx.ctx.plugin_conf[plugin.name]
      if conf then
        plugin.handler:body_filter(conf.value)
      end
    end
  end
end

function _M.log()
  if not ngx.ctx.error then

    local now = ngx.now()

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
      created_at = now
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
