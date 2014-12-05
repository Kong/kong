-- Copyright (C) Mashape, Inc.

local utils = require "apenode.utils"
local yaml = require "yaml"
local core = require "apenode.core.handler"

-- Define the plugins to load here, in the appropriate order
local plugins = {}

local _M = {}

function _M.init(configuration_path)
  -- Loading configuration
  configuration = yaml.load(utils.read_file(configuration_path))
  dao = require(configuration.dao.factory)

  -- Requiring the plugins
  table.insert(plugins, require("apenode.core.handler")) -- Adding the core first
  load_plugins()
end

function _M.access()
  ngx.ctx.start = ngx.now() -- Setting a property that will be available for every plugin
  for k, v in pairs(plugins) do -- Iterate over all the plugins
    v.access()
  end
  ngx.ctx.proxy_start = ngx.now() -- Setting a property that will be available for every plugin
end

function _M.content()
  for k, v in pairs(plugins) do -- Iterate over all the plugins
    v.content()
  end
end

function _M.rewrite()
  for k, v in pairs(plugins) do -- Iterate over all the plugins
    v.rewrite()
  end
end

function _M.header_filter()
  ngx.ctx.proxy_end = ngx.now() -- Setting a property that will be available for every plugin
  if not ngx.ctx.error then
    for k, v in pairs(plugins) do -- Iterate over all the plugins
      v.header_filter()
    end
  end
end

function _M.body_filter()
  for k, v in pairs(plugins) do -- Iterate over all the plugins
    v.body_filter()
  end
end

function _M.log()
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

  for k, v in pairs(plugins) do -- Iterate over all the plugins
    v.log()
  end
end

function load_plugins()
  local plugin_properties = {}

  for k, v in pairs(configuration.plugins) do
    local plugin_name = nil
    if type(v) == "table" then
      for k, v in pairs(v) do
        plugin_name = k

        --[[
        Normalizing the properties for an easier access into the plugins,
        like configuration.plugins[plugin_name].[property_name], for
        example: configuration.plugins.networklog.host
        --]]
        plugin_properties[plugin_name] = normalize_properties(v)
      end
    else
      plugin_name = v
    end

    table.insert(plugins, require("apenode.plugins." .. plugin_name .. ".handler"))
  end

  configuration.plugins = plugin_properties
end

function normalize_properties(properties)
  local result = {}

  if properties then
    for i, property in ipairs(properties) do
      if property then
        for k,v in pairs(property) do
          result[k] = v
        end
      end
    end
  end

  return result
end

return _M
