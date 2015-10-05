local BasePlugin = require "kong.plugins.base_plugin"
local body_filter = require "kong.plugins.response-transformer.body_filter"
local header_filter = require "kong.plugins.response-transformer.header_filter"

local ResponseTransformerHandler = BasePlugin:extend()

function ResponseTransformerHandler:new()
  ResponseTransformerHandler.super.new(self, "response-transformer")
end

function ResponseTransformerHandler:header_filter(conf)
  ResponseTransformerHandler.super.header_filter(self)
  header_filter.execute(conf)
end

function ResponseTransformerHandler:body_filter(conf)
  ResponseTransformerHandler.super.body_filter(self)
  body_filter.execute(conf)
end

ResponseTransformerHandler.PRIORITY = 800

return ResponseTransformerHandler
