local Object = require "kong.vendor.classic"
local BasePlugin = Object:extend()

local ngx_log = ngx.log
local DEBUG = ngx.DEBUG
local subsystem = ngx.config.subsystem

function BasePlugin:new(name)
  self._name = name
end

function BasePlugin:init_worker()
  ngx_log(DEBUG, "executing plugin \"", self._name, "\": init_worker")
end

if subsystem == "http" then
  function BasePlugin:certificate()
    ngx_log(DEBUG, "executing plugin \"", self._name, "\": certificate")
  end

  function BasePlugin:rewrite()
    ngx_log(DEBUG, "executing plugin \"", self._name, "\": rewrite")
  end

  function BasePlugin:access()
    ngx_log(DEBUG, "executing plugin \"", self._name, "\": access")
  end

  function BasePlugin:header_filter()
    ngx_log(DEBUG, "executing plugin \"", self._name, "\": header_filter")
  end

  function BasePlugin:body_filter()
    ngx_log(DEBUG, "executing plugin \"", self._name, "\": body_filter")
  end
elseif subsystem == "stream" then
  function BasePlugin:preread()
    ngx_log(DEBUG, "executing plugin \"", self._name, "\": preread")
  end
end

function BasePlugin:log()
  ngx_log(DEBUG, "executing plugin \"", self._name, "\": log")
end

return BasePlugin
