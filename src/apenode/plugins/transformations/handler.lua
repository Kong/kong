-- Copyright (C) Mashape, Inc.

local header_filter = require "apenode.plugins.transformations.header_filter"
local body_filter = require "apenode.plugins.transformations.body_filter"
local BasePlugin = require "apenode.base_plugin"

local Handler = {}
Handler.__index = Handler

setmetatable(Handler, {
  __index = BasePlugin, -- this is what makes the inheritance work
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

function Handler:_init(name)
  BasePlugin._init(self, name) -- call the base class constructor
end

function Handler:header_filter()
  BasePlugin.header_filter(self)
  header_filter.execute()
end

function Handler:body_filter()
  BasePlugin.body_filter(self)
  body_filter.execute()
end

return Handler
