-- Copyright (C) Mashape, Inc.

local BaseModel = require "apenode.models.base_model"

local Application = {
  _COLLECTION = "applications",
  _SCHEMA = {
    id = { type = "string", read_only = true },
    account_id = { type = "string", required = true },
    public_key = { type = "string", required = false },
    secret_key = { type = "string", required = true },
    created_at = { type = "number", read_only = true, default = os.time() }
  }
}

Application.__index = Application

setmetatable(Application, {
  __index = BaseModel,
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    return self:_init(...)
  end
})

function Application:_init(t)
  return BaseModel:_init(Application._COLLECTION, t, Application._SCHEMA)
end

return Application
