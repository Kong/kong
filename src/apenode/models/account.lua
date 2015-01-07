-- Copyright (C) Mashape, Inc.

local BaseModel = require "apenode.models.base_model"

local COLLECTION = "accounts"
local SCHEMA = {
  id = { type = "string", read_only = true },
  provider_id = { type = "string", required = false, unique = true },
  created_at = { type = "number", read_only = true, default = os.time() }
}

local Account = BaseModel:extend()

Account["_COLLECTION"] = COLLECTION
Account["_SCHEMA"] = SCHEMA

function Account:new(t, dao_factory)
  Account.super.new(self, COLLECTION, SCHEMA, t, dao_factory)
end

function Account.find_one(args, dao_factory)
  return Account.super._find_one(args, COLLECTION, dao_factory)
end

function Account.find(args, page, size, dao_factory)
  return Account.super._find(args, page, size, COLLECTION, dao_factory)
end

-- TODO: When deleting an account, also delete all his applications

return Account
