local utils = require "kong.tools.utils"
local runloop_handler = require "kong.runloop.handler"

local BasePlugin = require "kong.plugins.base_plugin"

local PLUGIN_NAME    = require("kong.plugins.exit-transformer").PLUGIN_NAME
local PLUGIN_VERSION = require("kong.plugins.exit-transformer").PLUGIN_VERSION

local function request_id()
  local ctx = ngx.ctx
  if ctx.admin_api then
    return ctx.admin_api.req_id
  end

  local ok, res = pcall(function() return ngx.var.set_request_id end)
  if ok then
    return res
  end

  return utils.uuid()
end

local function get_conf()
  -- If we use this function, instead of checking for something set on the
  -- access phase, we can completely bypass kong exit responses, on both
  -- ADMIN and PROXY sides. XXX: Do we want it?
  local ctx = ngx.ctx
  local plugins_iterator = runloop_handler.get_plugins_iterator()
  for plugin, plugin_conf in plugins_iterator:iterate(ctx, "access") do
    if plugin.name == PLUGIN_NAME then
      return plugin_conf
    end
  end
  return nil
end

-- XXX: Use proper cache, yadda yadda
-- Also, worker events yadda yadda :)
local transform_function_cache = setmetatable({}, { __mode = "k" })
local function get_transform_functions(config)
  local functions = transform_function_cache[config]
  if not functions then
    -- first call, go compile the functions
    functions = {}
    for _, fn_str in ipairs(config.functions) do
      local func1 = loadstring(fn_str)    -- load it
      local _, func2 = pcall(func1)       -- run it
      if type(func2) ~= "function" then
        -- old style (0.1.0), without upvalues
        table.insert(functions, func1)
      else
        -- this is a new function (0.2.0+), with upvalues
        table.insert(functions, func2)

        -- the first call to func1 above only initialized it, so run again
        func2()
      end
    end

    transform_function_cache[config] = functions
  end

  return ipairs(functions)
end


local _M = BasePlugin:extend()

_M.PRIORITY = 9999
_M.VERSION = PLUGIN_VERSION

function _M:new()
  _M.super.new(self, PLUGIN_NAME)
  kong.response.register_hook("exit", self.exit, self)
end


function _M:access(conf)
  _M.super.access(self)
  kong.ctx._exit_transformer_conf = conf
end


function _M:enabled()
  return kong.ctx._exit_transformer_conf ~= nil
end


function _M:exit(status, body, headers)

  --
  -- To completely hook into the exit function, including for ADMIN responses,
  -- instead of enabled (access phase) check, just look for get_conf()
  -- conf = get_conf()
  --

  if not self:enabled() then
    return status, body, headers
  end

  conf = kong.ctx._exit_transformer_conf

  if not conf then
    return status, body, headers
  end

  -- Some customers want a request id on kong exit responses
  kong.ctx._exit_request_id = request_id()

  for _, fn in get_transform_functions(conf) do
    status, body, _headers = fn(status, body, headers)
  end

  kong.ctx._exit_transformer_conf = nil

  return status, body, headers
end

return _M
