local utils = require "kong.tools.utils"
local runloop_handler = require "kong.runloop.handler"

local BasePlugin = require "kong.plugins.base_plugin"

local PLUGIN_NAME    = require("kong.plugins.exit-transformer").PLUGIN_NAME
local PLUGIN_VERSION = require("kong.plugins.exit-transformer").PLUGIN_VERSION


local function request_id()
  local ok, res = pcall(function() return ngx.var.set_request_id end)
  if ok then
    return res
  end

  return utils.uuid()
end


local function get_conf()
  -- Gets plugin configuration for the ctx, no matter the priority
  local ctx = ngx.ctx
  local plugins_iterator = runloop_handler.get_plugins_iterator()
  for plugin, plugin_conf in plugins_iterator:iterate(ctx, "access") do
    if plugin.name == PLUGIN_NAME then
      return plugin_conf
    end
  end
  return nil
end


-- XXX: Ideally use kong.cache, but functions cannot be serialized
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
end


function _M:exit(status, body, headers)
  -- Do not transform non proxy requests (ie: admin)
  if not ngx.ctx.is_proxy_request then
    return status, body, headers
  end

  -- Try to get plugin configuration for current context
  conf = get_conf()
  if not conf then
    return status, body, headers
  end

  -- Some customers want a request id on kong exit responses
  kong.ctx._exit_request_id = request_id()

  -- Reduce on status, body, headers through transform functions
  for _, fn in get_transform_functions(conf) do
    status, body, headers = fn(status, body, headers)
  end

  return status, body, headers
end

return _M
