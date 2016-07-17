local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local get_method = ngx.req.get_method

local function reverse(tbl)
  local reversed = {}

  for k, v in ipairs(tbl) do
    reversed[string.upper(v)] = k
  end

  return reversed
end

local MethodRestrictionHandler = BasePlugin:extend()

MethodRestrictionHandler.PRIORITY = 940

function MethodRestrictionHandler:new()
  MethodRestrictionHandler.super.new(self, "method-restriction")
end

function MethodRestrictionHandler:access(conf)
  MethodRestrictionHandler.super.access(self)

  local block = false
  local method = get_method()

  if conf.blacklist then
    block = reverse(conf.blacklist)[method]
  end

  if conf.whitelist then
    block = not reverse(conf.whitelist)[method]
  end

  if block then
    return responses.send_HTTP_METHOD_NOT_ALLOWED()
  end
end

return MethodRestrictionHandler
