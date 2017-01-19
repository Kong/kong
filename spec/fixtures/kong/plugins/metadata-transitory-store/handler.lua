local BasePlugin = require "kong.plugins.base_plugin"
-- local debug = require "kong.plugins.metadata-insertion.tool.debug"
local MetadataTransitoryStoreHandler = BasePlugin:extend()

MetadataTransitoryStoreHandler.PRIORITY = 100

function MetadataTransitoryStoreHandler:new()
  MetadataTransitoryStoreHandler.super.new(self, "metadata-transitory-store")
end

function MetadataTransitoryStoreHandler:init_worker()
  MetadataTransitoryStoreHandler.super.init_worker(self)
end

function MetadataTransitoryStoreHandler:access(conf)
  MetadataTransitoryStoreHandler.super.access(self)

  -- add data in metadata transitory store
  ngx.ctx.metadata_transitory_store = {
    {
      key = "location",
      value = "location-from-transitory"
    },
    {
      key = "third_party_api_key",
      value = "api-key-from-transitory"
    },
    {
      key = "field_only_available_in_transitory_store",
      value = "field_only_available_in_transitory_store"
    },
  }
end

return MetadataTransitoryStoreHandler
