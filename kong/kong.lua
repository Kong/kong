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

local IO = require "kong.tools.io"
local utils = require "kong.tools.utils"
local cache = require "kong.tools.database_cache"
local stringy = require "stringy"
local constants = require "kong.constants"
local responses = require "kong.tools.responses"

-- Define the plugins to load here, in the appropriate order
local plugins = {}

local _M = {}

local function get_now()
  return ngx.now() * 1000
end

local function load_plugin_conf(api_id, consumer_id, plugin_name)
  local cache_key = cache.plugin_configuration_key(plugin_name, api_id, consumer_id)

  local plugin = cache.get_or_set(cache_key, function()
    local rows, err = dao.plugins_configurations:find_by_keys {
        api_id = api_id,
        consumer_id = consumer_id ~= nil and consumer_id or constants.DATABASE_NULL_ID,
        name = plugin_name
      }
      if err then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
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
  -- TODO: this should be handled with other default config values
  configuration.plugins_available = configuration.plugins_available or {}

  print("Discovering used plugins")
  local db_plugins, err = dao.plugins_configurations:find_distinct()
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
      print("Loading plugin: "..v)
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

  -- resolver is always the first plugin as it is the one retrieving any needed information
  table.insert(loaded_plugins, 1, {
    resolver = true,
    name = "resolver",
    handler = require("kong.resolver.handler")()
  })

  if configuration.send_anonymous_reports then
    table.insert(loaded_plugins, 1, {
      reports = true,
      name = "reports",
      handler = require("kong.reports.handler")()
    })
  end

  return loaded_plugins
end

-- To be called by nginx's init_by_lua directive.
-- Execution:
--   - load the configuration from the path computed by the CLI
--   - instanciate the DAO Factory
--   - load the used plugins
--     - load all plugins if used and installed
--     - sort the plugins by priority
--     - load the resolver
--   - prepare DB statements
--
-- If any error during the initialization of the DAO or plugins,
-- it will be thrown and needs to be catched in init_by_lua.
function _M.init()
  -- Loading configuration
  configuration, dao = IO.load_configuration_and_dao(os.getenv("KONG_CONF"))

  -- Initializing plugins
  plugins = init_plugins()

  -- Prepare all collections' statements. Even if optional, this call is useful to check
  -- all statements are valid in advance.
  local err = dao:prepare()
  if err then
    error(err)
  end
  ngx.update_time()
end

-- Calls `init_worker()` on eveyr loaded plugin
function _M.exec_plugins_init_worker()
  for _, plugin in ipairs(plugins) do
    plugin.handler:init_worker()
  end
end

function _M.exec_plugins_certificate()
  ngx.ctx.plugin_conf = {}

  for _, plugin in ipairs(plugins) do
    if ngx.ctx.api then
      ngx.ctx.plugin_conf[plugin.name] = load_plugin_conf(ngx.ctx.api.id, nil, plugin.name)
    end

    local conf = ngx.ctx.plugin_conf[plugin.name]
    if not ngx.ctx.stop_phases and (plugin.resolver or conf) then
      plugin.handler:certificate(conf and conf.value or nil)
    end
  end

  return
end

-- Calls `access()` on every loaded plugin
function _M.exec_plugins_access()
  -- Setting a property that will be available for every plugin
  ngx.ctx.started_at = get_now()
  ngx.ctx.plugin_conf = {}

  -- Iterate over all the plugins
  for _, plugin in ipairs(plugins) do
    if ngx.ctx.api then
      ngx.ctx.plugin_conf[plugin.name] = load_plugin_conf(ngx.ctx.api.id, nil, plugin.name)
      local consumer_id = ngx.ctx.authenticated_entity and ngx.ctx.authenticated_entity.consumer_id or nil
      if consumer_id then
        local app_plugin_conf = load_plugin_conf(ngx.ctx.api.id, consumer_id, plugin.name)
        if app_plugin_conf then
          ngx.ctx.plugin_conf[plugin.name] = app_plugin_conf
        end
      end
    end
    local conf = ngx.ctx.plugin_conf[plugin.name]
    if not ngx.ctx.stop_phases and (plugin.resolver or conf) then
      plugin.handler:access(conf and conf.value or nil)
    end
  end
  -- Append any modified querystring parameters
  local parts = stringy.split(ngx.var.backend_url, "?")
  local final_url = parts[1]
  if utils.table_size(ngx.req.get_uri_args()) > 0 then
    final_url = final_url.."?"..ngx.encode_args(ngx.req.get_uri_args())
  end
  ngx.var.backend_url = final_url
  ngx.ctx.proxy_started_at = get_now()
end

-- Calls `header_filter()` on every loaded plugin
function _M.exec_plugins_header_filter()
  ngx.ctx.proxy_ended_at = get_now()

  if not ngx.ctx.stop_phases then
    ngx.header["Via"] = constants.NAME.."/"..constants.VERSION

    for _, plugin in ipairs(plugins) do
      local conf = ngx.ctx.plugin_conf[plugin.name]
      if conf then
        plugin.handler:header_filter(conf.value)
      end
    end
  end
end

-- Calls `body_filter()` on every loaded plugin
function _M.exec_plugins_body_filter()
  if not ngx.ctx.stop_phases then
    for _, plugin in ipairs(plugins) do
      local conf = ngx.ctx.plugin_conf[plugin.name]
      if conf then
        plugin.handler:body_filter(conf.value)
      end
    end
  end
  ngx.ctx.ended_at = get_now()
end

-- Calls `log()` on every loaded plugin
function _M.exec_plugins_log()
  if not ngx.ctx.stop_phases then
    -- Creating the log variable that will be serialized
    local message = {
      request = {
        uri = ngx.var.request_uri,
        request_uri = ngx.var.scheme.."://"..ngx.var.host..":"..ngx.var.server_port..ngx.var.request_uri,
        querystring = ngx.req.get_uri_args(), -- parameters, as a table
        method = ngx.req.get_method(), -- http method
        headers = ngx.req.get_headers(),
        size = ngx.var.request_length
      },
      response = {
        status = ngx.status,
        headers = ngx.resp.get_headers(),
        size = ngx.var.bytes_sent
      },
      latencies = {
        kong = (ngx.ctx.ended_at - ngx.ctx.started_at) - (ngx.ctx.proxy_ended_at - ngx.ctx.proxy_started_at),
        proxy = ngx.ctx.proxy_ended_at - ngx.ctx.proxy_started_at,
        total = ngx.ctx.ended_at - ngx.ctx.started_at
      },
      authenticated_entity = ngx.ctx.authenticated_entity,
      api = ngx.ctx.api,
      client_ip = ngx.var.remote_addr,
      started_at = ngx.ctx.started_at
    }

    ngx.ctx.log_message = message

    for _, plugin in ipairs(plugins) do
      local conf = ngx.ctx.plugin_conf[plugin.name]
      if conf or plugin.reports then
        plugin.handler:log(conf and conf.value or nil)
      end
    end
  end
end

return _M
