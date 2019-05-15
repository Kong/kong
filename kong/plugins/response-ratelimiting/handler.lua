-- Copyright (C) Kong Inc.

local access = require "kong.plugins.response-ratelimiting.access"
local log = require "kong.plugins.response-ratelimiting.log"
local header_filter = require "kong.plugins.response-ratelimiting.header_filter"


local ResponseRateLimitingHandler = {}


function ResponseRateLimitingHandler:access(conf)
  access.execute(conf)
end


function ResponseRateLimitingHandler:header_filter(conf)
  header_filter.execute(conf)
end


function ResponseRateLimitingHandler:log(conf)
  local ctx = kong.ctx.plugin
  if not ctx.stop_log and ctx.usage then
    log.execute(conf, ctx.identifier, ctx.current_timestamp, ctx.increments, ctx.usage)
  end
end


ResponseRateLimitingHandler.PRIORITY = 900
ResponseRateLimitingHandler.VERSION = "2.0.0"


return ResponseRateLimitingHandler
