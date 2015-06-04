local BasePlugin = require "kong.plugins.base_plugin"
local init_worker = require "kong.reports.init_worker"
local log = require "kong.reports.log"

local ReportsHandler = BasePlugin:extend()

function ReportsHandler:new()
  ReportsHandler.super.new(self, "reports")
end

function ReportsHandler:init_worker()
  ReportsHandler.super.init_worker(self)
  init_worker.execute()
end

function ReportsHandler:log()
  ReportsHandler.super.log(self)
  log.execute()
end

return ReportsHandler
