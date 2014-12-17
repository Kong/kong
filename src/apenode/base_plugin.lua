-- Copyright (C) Mashape, Inc.

local BasePlugin = {}
BasePlugin.__index = BasePlugin

setmetatable(BasePlugin, {
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

function BasePlugin:_init(name)
  self._name = name
end

function BasePlugin:access()
  ngx.log(ngx.DEBUG, " executing plugin " .. self._name .. ": access")
end

function BasePlugin:header_filter()
  ngx.log(ngx.DEBUG, " executing plugin " .. self._name .. ": header_filter")
end

function BasePlugin:body_filter()
  ngx.log(ngx.DEBUG, " executing plugin " .. self._name .. ": body_filter")
end

function BasePlugin:log()
  ngx.log(ngx.DEBUG, " executing plugin " .. self._name .. ": log")
end

return BasePlugin