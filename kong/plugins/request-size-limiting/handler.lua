-- Copyright (C) Mashape, Inc.

local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.request-size-limiting.access"

local RequestSizeLimitingHandler = BasePlugin:extend()

function RequestSizeLimitingHandler:new()
  RequestSizeLimitingHandler.super.new(self, "request-size-limiting")
end

function RequestSizeLimitingHandler:access(conf)
  RequestSizeLimitingHandler.super.access(self)
  access.execute(conf)
end

RequestSizeLimitingHandler.PRIORITY = 950

return RequestSizeLimitingHandler
