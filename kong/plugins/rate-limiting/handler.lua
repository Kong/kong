-- Copyright (C) Mashape, Inc.

local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.rate-limiting.access"

local RateLimitingHandler = BasePlugin:extend()

function RateLimitingHandler:new()
  RateLimitingHandler.super.new(self, "rate-limiting")
end

function RateLimitingHandler:access(conf)
  RateLimitingHandler.super.access(self)
  access.execute(conf)
end

RateLimitingHandler.PRIORITY = 900

return RateLimitingHandler
