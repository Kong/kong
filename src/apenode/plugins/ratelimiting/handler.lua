-- Copyright (C) Mashape, Inc.

local BasePlugin = require "apenode.base_plugin"
local access = require "apenode.plugins.ratelimiting.access"

local function check_period(v)
  if v == "second" or v == "minute" or v == "hour" or v == "day" or v == "day" or v == "month" or v == "year" then
    return true
  else
    return false, "Available values are: second, minute, hour, day, month, year"
  end
end

local RateLimitingHandler = BasePlugin:extend()

RateLimitingHandler["_SCHEMA"] = {
  limit = { type = "number", required = true },
  period = { type = "string", required = true, func = check_period }
}

function RateLimitingHandler:new()
  RateLimitingHandler.super.new(self, "ratelimiting")
end

function RateLimitingHandler:access(conf)
  RateLimitingHandler.super.access(self)
  access.execute(conf)
end

return RateLimitingHandler
