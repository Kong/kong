-- Copyright (C) Mashape, Inc.

local BaseModel = require "apenode.models.base_model"

local Account = {
  _COLLECTION = "accounts",
  _SCHEMA = {
    id = { type = "string", read_only = true },
    provider_id = { type = "string", required = false },
    created_at = { type = "number", read_only = true, default = os.time() }
  }
}

Account.__index = Account

setmetatable(Account, {
  __index = BaseModel,
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    return self:_init(...)
  end
})

function Account:_init(t)
  return BaseModel:_init(Account._COLLECTION, t, Account._SCHEMA)
end

return Account
