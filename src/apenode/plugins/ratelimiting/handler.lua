-- Copyright (C) Mashape, Inc.

local BasePlugin = require "apenode.base_plugin"
local access = require "apenode.plugins.ratelimiting.access"

local RateLimitingHandler = BasePlugin:extend()

local SCHEMA = {
  limit = { type = "number", required = true },
  period = { type = "string", required = true, enum = { "second", "minute", "hour", "day", "month", "year" } }
}

function RateLimitingHandler:new()
  self._schema = SCHEMA
  RateLimitingHandler.super.new(self, "ratelimiting")
end

function RateLimitingHandler:access(conf)
  RateLimitingHandler.super.access(self)
  access.execute(conf)
end

return RateLimitingHandler
