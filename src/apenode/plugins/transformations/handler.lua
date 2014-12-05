-- Copyright (C) Mashape, Inc.

local BasePlugin = require "apenode.base_plugin"
local header_filter = require "apenode.plugins.transformations.header_filter"
local body_filter = require "apenode.plugins.transformations.body_filter"

local TransformationsHandler = {}
TransformationsHandler.__index = TransformationsHandler

setmetatable(TransformationsHandler, {
  __index = BasePlugin, -- this is what makes the inheritance work
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

function TransformationsHandler:_init(name)
  BasePlugin:_init(name) -- call the base class constructor
end

function TransformationsHandler:header_filter()
  BasePlugin:header_filter()
  header_filter.execute()
end

function TransformationsHandler:body_filter()
  BasePlugin:body_filter()
  body_filter.execute()
end

return TransformationsHandler
