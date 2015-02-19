-- Copyright (C) Mashape, Inc.

local access = require "kong.core.access"
local header_filter = require "kong.core.header_filter"
local BasePlugin = require "kong.base_plugin"

local CoreHandler = BasePlugin:extend()

function CoreHandler:new()
  CoreHandler.super.new(self, "core")
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
