-- Copyright (C) Mashape, Inc.

local BaseModel = require "apenode.models.base_model"

local COLLECTION = "plugins"
local SCHEMA = {
  id = { type = "string", read_only = true },
  api_id = { type = "string", required = true },
  application_id = { type = "string", required = false },
  name = { type = "string", required = true },
  value = { type = "table", required = true }
}

local Plugin = {
  _COLLECTION = COLLECTION,
  _SCHEMA = SCHEMA
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
  return BaseModel:_init(COLLECTION, t, SCHEMA)
end

function Plugin.find_one(args)
  return BaseModel._find_one(COLLECTION, args)
end

function Plugin.find(args, page, size)
  return BaseModel._find(COLLECTION, args, page, size)
end

function Plugin.find_and_delete(args)
  return BaseModel._find_and_delete(COLLECTION, args)
end

return Plugin
