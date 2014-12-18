-- Copyright (C) Mashape, Inc.

local BaseModel = require "apenode.models.base_model"

local COLLECTION = "apis"
local SCHEMA = {
  id = { type = "string", read_only = true },
  name = { type = "string", required = true, unique = true },
  public_dns = { type = "string", required = true, unique = true, regex = "(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9])\\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\\-]*[A-Za-z0-9])" },
  target_url = { type = "string", required = true },
  authentication_type = { type = "string", required = true },
  authentication_key_names = { type = "table", required = false },
  created_at = { type = "number", read_only = true, default = os.time() }
}

local Api = {
  _COLLECTION = COLLECTION,
  _SCHEMA = SCHEMA
}

Api.__index = Api

setmetatable(Api, {
  __index = BaseModel,
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    return self:_init(...)
  end
})

function Api:_init(t)
  return BaseModel:_init(COLLECTION, t, SCHEMA)
end

function Api.find_one(args)
  return BaseModel._find_one(COLLECTION, args)
end

function Api.find(args, page, size)
  return BaseModel._find(COLLECTION, args, page, size)
end

function Api.find_and_delete(args)
  return BaseModel._find_and_delete(COLLECTION, args)
end

-- TODO: When deleting an API, also delete all his plugins/metrics

return Api
