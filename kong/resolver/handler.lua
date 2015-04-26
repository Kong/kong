local access = require "kong.resolver.access"
local header_filter = require "kong.resolver.header_filter"
local BasePlugin = require "kong.plugins.base_plugin"

local CoreHandler = BasePlugin:extend()

function CoreHandler:new()
  CoreHandler.super.new(self, "resolver")
end

function CoreHandler:access(conf)
  CoreHandler.super.access(self)
  access.execute(conf)
end

function CoreHandler:header_filter(conf)
  CoreHandler.super.header_filter(self)
  header_filter.execute(conf)
end

return CoreHandler
