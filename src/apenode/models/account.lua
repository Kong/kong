-- Copyright (C) Mashape, Inc.

local BaseModel = require "apenode.models.base_model"

local COLLECTION = "accounts"
local SCHEMA = {
  id = { type = "string", read_only = true },
  provider_id = { type = "string", required = false, unique = true },
  created_at = { type = "number", read_only = true, default = os.time() }
}

local Account = {
  _COLLECTION = COLLECTION,
  _SCHEMA = SCHEMA
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
  return BaseModel:_init(COLLECTION, t, SCHEMA)
end

function Account.find_one(args)
  return BaseModel._find_one(COLLECTION, args)
end

function Account.find(args, page, size)
  return BaseModel._find(COLLECTION, args, page, size)
end

function Account.find_and_delete(args)
  return BaseModel._find_and_delete(COLLECTION, args)
end

-- TODO: When deleting an account, also delete all his applications

return Account
