-- Copyright (C) Kong Inc.

local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.response-ratelimiting.access"
local log = require "kong.plugins.response-ratelimiting.log"
local header_filter = require "kong.plugins.response-ratelimiting.header_filter"


local ResponseRateLimitingHandler = BasePlugin:extend()


function ResponseRateLimitingHandler:new()
  ResponseRateLimitingHandler.super.new(self, "response-ratelimiting")
end


function ResponseRateLimitingHandler:access(conf)
  ResponseRateLimitingHandler.super.access(self)
  access.execute(conf)
end


function ResponseRateLimitingHandler:header_filter(conf)
  ResponseRateLimitingHandler.super.header_filter(self)
  header_filter.execute(conf)
end


function ResponseRateLimitingHandler:log(conf)
  local ctx = kong.ctx.plugin
  if not ctx.stop_log and ctx.usage then
    ResponseRateLimitingHandler.super.log(self)
    log.execute(conf, ctx.identifier, ctx.current_timestamp, ctx.increments, ctx.usage)
  end
end


ResponseRateLimitingHandler.PRIORITY = 900
ResponseRateLimitingHandler.VERSION = "1.0.0"


return ResponseRateLimitingHandler
