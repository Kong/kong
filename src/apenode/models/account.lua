-- Copyright (C) Mashape, Inc.

local utils = require "apenode.tools.utils"
local BaseModel = require "apenode.models.base_model"

local COLLECTION = "accounts"
local SCHEMA = {
  id = { type = "id", read_only = true },
  provider_id = { type = "string", unique = true },
  created_at = { type = "timestamp", default = utils.get_utc }
}

local Account = BaseModel:extend()

Account["_COLLECTION"] = COLLECTION
Account["_SCHEMA"] = SCHEMA

function Account:new(t, dao_factory)
  Account.super.new(self, COLLECTION, SCHEMA, t, dao_factory)
end

function Account.find_one(args, dao_factory)
  local data, err =  Account.super._find_one(args, dao_factory[COLLECTION])
  if data then
    data = Account(data, dao_factory)
  end
  return data, err
end

function Account.find(args, page, size, dao_factory)
  local data, total, err = Account.super._find(args, page, size, dao_factory[COLLECTION])
  if data then
    for i,v in ipairs(data) do
      data[i] = Account(v, dao_factory)
    end
  end
  return data, total, err
end

-- TODO: When deleting an account, also delete all his applications

return Account
