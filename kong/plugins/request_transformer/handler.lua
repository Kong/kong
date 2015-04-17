-- Copyright (C) Mashape, Inc.

local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.request_transformer.access"

local RequestTransformerHandler = BasePlugin:extend()

function RequestTransformerHandler:new()
  RequestTransformerHandler.super.new(self, "request_transformer")
end

function RequestTransformerHandler:access(conf)
  RequestTransformerHandler.super.access(self)
  access.execute(conf)
end

RequestTransformerHandler.PRIORITY = 800

return RequestTransformerHandler
