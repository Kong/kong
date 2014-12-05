-- Copyright (C) Mashape, Inc.

local log = require "apenode.plugins.networklog.log"
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

function Handler:log()
  BasePlugin.log(self)
  log.execute()
end

return Handler