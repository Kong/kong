-- Copyright (C) Mashape, Inc.

local BasePlugin = require "apenode.base_plugin"
local access = require "apenode.plugins.ratelimiting.access"

local RateLimitingHandler = {}
RateLimitingHandler.__index = RateLimitingHandler

setmetatable(RateLimitingHandler, {
  __index = BasePlugin, -- this is what makes the inheritance work
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

function RateLimitingHandler:_init(name)
  BasePlugin._init(self, name) -- call the base class constructor
end

function RateLimitingHandler:access()
  BasePlugin.access(self)
  access.execute()
end

return RateLimitingHandler
