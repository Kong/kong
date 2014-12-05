-- Copyright (C) Mashape, Inc.

local BasePlugin = require "apenode.base_plugin"
local access = require "apenode.plugins.authentication.access"

local AccessHandler = {}
AccessHandler.__index = AccessHandler

setmetatable(AccessHandler, {
  __index = BasePlugin, -- this is what makes the inheritance work
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

function AccessHandler:_init(name)
  BasePlugin._init(self, name) -- call the base class constructor
end

function AccessHandler:access()
  BasePlugin.access(self)
  access.execute()
end

return AccessHandler
