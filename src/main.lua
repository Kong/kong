-- Copyright (C) Mashape, Inc.

utils = require "apenode.utils"
local yaml = require "yaml"
local PluginModel = require "apenode.models.plugin"

-- Define the plugins to load here, in the appropriate order
local plugins = {}

local _M = {}

local function load_plugin_conf(api_id, application_id, plugin_name)
  local res, err = PluginModel.find_one({
    api_id = api_id,
    application_id = application_id,
    name = plugin_name
  }, dao)

  if err then
    ngx.log(ngx.ERROR, err)
    return nil
  end

  return res
end

function _M.init(configuration_path)
  -- Loading configuration
  configuration = yaml.load(utils.read_file(configuration_path))
  dao_configuration = configuration.databases_available[configuration.database]
  if dao_configuration == nil then
    ngx.log(ngx.ERROR, "No dao \""..configuration.database.."\" defined in "..configuration_path)
  end

  -- Loading DAO
  local dao_factory = require("apenode.dao." .. configuration.database)
  dao = dao_factory(dao_configuration.properties)

  -- core is the first plugin
  table.insert(plugins, {
    name = "core",
    handler = require("apenode.core.handler")()
  })

  -- Loading defined plugins
  for _,v in ipairs(configuration.plugins_enabled) do
    table.insert(plugins, {
      name = v,
      handler = require("apenode.plugins." .. v .. ".handler")()
    })
  end
end

function _M.access()
  -- Setting a property that will be available for every plugin
  ngx.ctx.start = ngx.now()
  ngx.ctx.plugin_conf = {}

  -- Iterate over all the plugins
  for _, v in ipairs(plugins) do
    if ngx.ctx.api then
      ngx.ctx.plugin_conf[v.name] = load_plugin_conf(ngx.ctx.api.id, nil, v.name) -- Loading the "API-specific" configuration
    end

    if ngx.ctx.authenticated_entity then
      local plugin_conf = load_plugin_conf(ngx.ctx.api.id, ngx.ctx.authenticated_entity.id, v.name)
      if plugin_conf then -- Override only if not nil
        ngx.ctx.plugin_conf[v.name] = plugin_conf
      end
    end

    if not ngx.ctx.error then
      local conf = ngx.ctx.plugin_conf[v.name]
      if not ngx.ctx.api then -- If not ngx.ctx.api then it's the core plugin
        v.handler:access(nil)
      elseif conf then
        v.handler:access(conf.value)
      end
    end
  end

  ngx.ctx.proxy_start = ngx.now() -- Setting a property that will be available for every plugin
end

function _M.header_filter()
  ngx.ctx.proxy_end = ngx.now() -- Setting a property that will be available for every plugin

  if not ngx.ctx.error then
    for _, v in ipairs(plugins) do -- Iterate over all the plugins
      local conf = ngx.ctx.plugin_conf[v.name]
      if conf then
        v.handler:header_filter(conf.value)
      end
    end
  end
end

function _M.body_filter()
  if not ngx.ctx.error then
    for _, v in ipairs(plugins) do -- Iterate over all the plugins
      local conf = ngx.ctx.plugin_conf[v.name]
      if conf then
        v.handler:body_filter(conf.value)
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
    for _, v in ipairs(plugins) do -- Iterate over all the plugins
      local conf = ngx.ctx.plugin_conf[v.name]
      if conf then
        v.handler:log(conf.value)
      end
    end
  end
end

return _M
