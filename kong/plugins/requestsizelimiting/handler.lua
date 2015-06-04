-- Copyright (C) Mashape, Inc.

local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.requestsizelimiting.access"

local RequestSizeLimitingHandler = BasePlugin:extend()

function RequestSizeLimitingHandler:new()
  RequestSizeLimitingHandler.super.new(self, "requestsizelimiting")
end

function RequestSizeLimitingHandler:access(conf)
  RequestSizeLimitingHandler.super.access(self)
  access.execute(conf)
end

RequestSizeLimitingHandler.PRIORITY = 950

return RequestSizeLimitingHandler
