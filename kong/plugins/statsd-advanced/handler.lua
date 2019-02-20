local BasePlugin      = require "kong.plugins.base_plugin"
local statsd_handler  = require "kong.vitals.prometheus.statsd.handler"
local log_helper      = require "kong.plugins.statsd-advanced.log_helper"


local StatsdHandler = BasePlugin:extend()
StatsdHandler.PRIORITY = 11
StatsdHandler.VERSION = "0.1.2"


function StatsdHandler:new()
  StatsdHandler.super.new(self, "statsd-advanced")
end

function StatsdHandler:init_worker()
  StatsdHandler.super.init_worker(self)
end


function StatsdHandler:log(conf)
  StatsdHandler.super.log(self)

  log_helper:log(statsd_handler, conf, ngx.status)
end


return StatsdHandler
