-- Copyright (C) Mashape, Inc.

local BaseModel = require "apenode.models.base_model"

local Api = {
  _COLLECTION = "apis",
  _SCHEMA = {
    id = { type = "string", read_only = true },
    name = { type = "string", required = true },
    public_dns = { type = "string", required = true },
    target_url = { type = "string", required = true },
    created_at = { type = "number", read_only = true, default = os.time() }
  }
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
  return BaseModel:_init(Api._COLLECTION, t, Api._SCHEMA)
end

return Api
