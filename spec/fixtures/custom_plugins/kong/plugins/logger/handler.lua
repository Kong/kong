local BasePlugin = require "kong.plugins.base_plugin"


local LoggerHandler = BasePlugin:extend()


LoggerHandler.PRIORITY = 1000


function LoggerHandler:new()
  LoggerHandler.super.new(self, "logger")
end


function LoggerHandler:init_worker(conf)
  LoggerHandler.super.init_worker(self)

  kong.log("init_worker phase")
end


function LoggerHandler:certificate(conf)
  LoggerHandler.super.certificate(self)

  kong.log("certificate phase")
end


function LoggerHandler:rewrite(conf)
  LoggerHandler.super.rewrite(self)

  kong.log("rewrite phase")
end


function LoggerHandler:access(conf)
  LoggerHandler.super.access(self)

  kong.log("access phase")
end


function LoggerHandler:header_filter(conf)
  LoggerHandler.super.header_filter(self)

  kong.log("header_filter phase")
end


function LoggerHandler:body_filter(conf)
  LoggerHandler.super.body_filter(self)

  kong.log("body_filter phase")
end


function LoggerHandler:log(conf)
  LoggerHandler.super.log(self)

  kong.log("log phase")
end


return LoggerHandler
