local Object = require "classic"
local BasePlugin = Object:extend()

function BasePlugin:new(name)
    self._name = name
end

function BasePlugin:init_worker()
    ngx.log(ngx.DEBUG, " executing plugin \"" .. self._name .. "\": init_worker")
end

function BasePlugin:certificate()
    ngx.log(ngx.DEBUG, " executing plugin \"" .. self._name .. "\": certificate")
end

function BasePlugin:access()
    ngx.log(ngx.DEBUG, " executing plugin \"" .. self._name .. "\": access")
end

function BasePlugin:header_filter()
    ngx.log(ngx.DEBUG, " executing plugin \"" .. self._name .. "\": header_filter")
end

function BasePlugin:body_filter()
    ngx.log(ngx.DEBUG, " executing plugin \"" .. self._name .. "\": body_filter")
end

function BasePlugin:log()
    ngx.log(ngx.DEBUG, " executing plugin \"" .. self._name .. "\": log")
end

return BasePlugin
