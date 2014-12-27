-- Copyright (C) Mashape, Inc.

local access = require "apenode.core.access"
local header_filter = require "apenode.core.header_filter"
local BasePlugin = require "apenode.base_plugin"

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
