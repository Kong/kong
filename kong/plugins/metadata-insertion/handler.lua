local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.metadata-insertion.access"

local MetadataInsertionHandler = BasePlugin:extend()

function MetadataInsertionHandler:new()
  MetadataInsertionHandler.super.new(self, "metadata-insertion")
end

function MetadataInsertionHandler:access(conf)
  MetadataInsertionHandler.super.access(self)
  access.execute(conf)
end

return MetadataInsertionHandler
