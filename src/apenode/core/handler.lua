-- Copyright (C) Mashape, Inc.

local access = require "apenode.core.access"
local header_filter = require "apenode.core.header_filter"
local BasePlugin = require "apenode.base_plugin"

local CoreHandler = {}
CoreHandler.__index = CoreHandler

setmetatable(CoreHandler, {
  __index = BasePlugin, -- this is what makes the inheritance work
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

function CoreHandler:_init(name)
  BasePlugin:_init(name) -- call the base class constructor
end

function CoreHandler:access()
  BasePlugin:access()
  access.execute()
end

function CoreHandler:header_filter()
  BasePlugin:access()
  header_filter.execute()
end

return CoreHandler
