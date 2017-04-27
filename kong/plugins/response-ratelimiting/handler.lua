-- Copyright (C) Mashape, Inc.

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
  if not ngx.ctx.stop_log and ngx.ctx.usage then
    ResponseRateLimitingHandler.super.log(self)
    log.execute(conf, ngx.ctx.api.id, ngx.ctx.identifier, ngx.ctx.current_timestamp, ngx.ctx.increments, ngx.ctx.usage)
  end
end

ResponseRateLimitingHandler.PRIORITY = 1100

return ResponseRateLimitingHandler
