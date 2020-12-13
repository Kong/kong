-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson.safe"

local runloop_handler = require "kong.runloop.handler"
local sandbox = require "kong.tools.sandbox"

local BasePlugin = require "kong.plugins.base_plugin"

local PLUGIN_NAME    = require("kong.plugins.exit-transformer").PLUGIN_NAME
local PLUGIN_VERSION = require("kong.plugins.exit-transformer").PLUGIN_VERSION


local function get_conf()
  -- Gets plugin configuration for the ctx, no matter the priority

  -- detect if it's an "unknown" call, so no service. We used to rely on
  -- request having no workspace context
  -- XXX: this is not using the pdk call. The pdk call cannot be run on the
  -- error phase, which funnily enough is most of the cases we want this
  -- plugin to run :) be attentive of route being on any other ctx
  local unknown = ngx.ctx.route == nil

  -- Not really needed, but a hack because get_workspace might return an
  -- empty {} to signal... something? AFAIK, this is fixed on 2.0 already,
  -- this solution makes it so it won't work on neither version of kong.

  local plugins_iterator = runloop_handler.get_plugins_iterator()

  for plugin, plugin_conf in plugins_iterator:iterate("access", ngx.ctx) do

    if plugin.name ~= PLUGIN_NAME then
      goto continue
    end

    -- it's very important that this filtering happens here and not once we
    -- already have a config. Since plugin confs applying globally on
    -- different workspaces would collide here and rely only on the first
    -- match
    if unknown and not plugin_conf.handle_unknown then
      goto continue
    end

    if ngx.ctx.KONG_UNEXPECTED and not plugin_conf.handle_unexpected then
      goto continue
    end

    do
      return plugin_conf
    end

    ::continue::
  end

  return nil
end

local _M = BasePlugin:extend()

_M.PRIORITY = 9999
_M.VERSION = PLUGIN_VERSION

function _M:new()
  _M.super.new(self, PLUGIN_NAME)
end

function _M:init_worker()
  kong.response.register_hook("exit", self.exit, self)
  kong.response.register_hook("send", self.exit, self)
end

function _M:access(conf)
  _M.super.access(self)
end


local function_cache = setmetatable({}, { __mode = "k" })

local function no_op(err)
  return function(status, body, headers)
    kong.log.err(err)
    return status, body, headers
  end
end

local function get_functions(conf)
  if function_cache[conf] then return function_cache[conf] end

  local functions = {}

  for _, fn_str in ipairs(conf.functions) do
    -- XXX kong request always available
    local env = {
      kong = {
        request = setmetatable({}, { __index = kong.request })
      }
    }

    local f, err = sandbox.validate_function(fn_str, { env = env })
    if err then f = no_op(err) end

    table.insert(functions, f)
  end

  function_cache[conf] = functions

  return functions
end

function _M:exit(status, body, headers)
  -- Do not transform admin requests
  if not ngx.ctx.is_proxy_request then
    return status, body, headers
  end

  -- Try to get plugin configuration for current context
  local conf = get_conf()
  if not conf then
    return status, body, headers
  end

  -- XXX Both exit and send now contain body as plaintext always
  -- try to convert back to message and if that fails give it raw
  local data, err = cjson.decode(body)

  if not err then
    body = data
  end

  local functions = get_functions(conf)

  -- Reduce on status, body, headers through transform functions
  for _, fn in ipairs(functions) do
    status, body, headers = fn(status, body, headers)
  end

  return status, body, headers
end

return _M
