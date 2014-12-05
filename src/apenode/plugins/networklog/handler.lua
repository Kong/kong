-- Copyright (C) Mashape, Inc.

local BasePlugin = require "apenode.base_plugin"
local log = require "apenode.plugins.networklog.log"

local NetworkLogHandler = {}
NetworkLogHandler.__index = NetworkLogHandler

setmetatable(NetworkLogHandler, {
  __index = BasePlugin, -- this is what makes the inheritance work
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

function NetworkLogHandler:_init(name)
  BasePlugin:_init(name)
end

function NetworkLogHandler:log()
  BasePlugin:log()
  log.execute()
end

return NetworkLogHandler
