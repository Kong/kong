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

function Account:new(t)
  Account.super.new(self, COLLECTION, SCHEMA, t)
end

function Account.find_one(args)
  return Account.super._find_one(COLLECTION, args)
end

function Account.find(args, page, size)
  return Account.super._find(COLLECTION, args, page, size)
end

function Account.find_and_delete(args)
  return Account.super._find_and_delete(COLLECTION, args)
end

-- TODO: When deleting an account, also delete all his applications

return Account
