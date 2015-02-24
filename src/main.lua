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
  local rows, err = dao.plugins:find_by_keys {
    api_id = api_id,
    application_id = application_id ~= nil and application_id or constants.DATABASE_NULL_ID,
    name = plugin_name
  }

  if err then
    ngx.log(ngx.ERROR, err)
    return nil
  end

  if #rows > 0 then
    local plugin = table.remove(rows, 1)
    if plugin.enabled then
      return plugin
    end
  end

  return nil
end

function _M.init()
  -- Loading configuration
  configuration, dao = utils.load_configuration_and_dao(os.getenv("KONG_CONF"))

  dao:prepare()

  -- core is the first plugin
  table.insert(plugins, {
    core = true,
    name = "core",
    handler = require("kong.core.handler")()
  })

  -- Loading defined plugins
  for _, plugin_name in ipairs(configuration.plugins_enabled) do
    table.insert(plugins, {
      name = plugin_name,
      handler = require("kong.plugins."..plugin_name..".handler")()
    })
  end
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
