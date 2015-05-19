local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.datausage.access"
local header_filter = require "kong.plugins.datausage.header_filter"
local log = require "kong.plugins.datausage.log"

local DataUsageHandler = BasePlugin:extend()

function DataUsageHandler:new()
  DataUsageHandler.super.new(self, "datausage")
end

function DataUsageHandler:access(conf)
  DataUsageHandler.super.access(self)
  access.execute(conf)
end

function DataUsageHandler:log(conf)
  DataUsageHandler.super.log(self)
  log.execute(conf)
end

DataUsageHandler.PRIORITY = 800

return DataUsageHandler
