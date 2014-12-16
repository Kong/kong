-- Copyright (C) Mashape, Inc.

local BaseModel = require "apenode.models.base_model"

local Plugin = {
  _COLLECTION = "plugins",
  _SCHEMA = {
    api_id = { type = "string", required = true },
    application_id = { type = "string", required = false },
    name = { type = "string", required = true },
    value = { type = "table", required = true }
  }
}

Plugin.__index = Plugin

setmetatable(Plugin, {
  __index = BaseModel,
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    return self:_init(...)
  end
})

function Plugin:_init(t)
  return BaseModel:_init(Plugin._COLLECTION, t, Plugin._SCHEMA)
end

return Plugin
