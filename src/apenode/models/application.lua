-- Copyright (C) Mashape, Inc.

local utils = require "apenode.tools.utils"
local AccountModel = require "apenode.models.account"
local BaseModel = require "apenode.models.base_model"

local function check_account_id(account_id, t, dao_factory)
  if AccountModel.find_one({id = account_id}, dao_factory) then
    return true
  else
    return false, "Account not found"
  end
end

local COLLECTION = "applications"
local SCHEMA = {
  id = { type = "string", read_only = true },
  account_id = { type = "string", required = true, func = check_account_id },
  public_key = { type = "string", required = false },
  secret_key = { type = "string", required = true, unique = true },
  created_at = { type = "number", read_only = false, default = utils.get_utc }
}

local Application = BaseModel:extend()
Application["_COLLECTION"] = COLLECTION
Application["_SCHEMA"] = SCHEMA

function Application:new(t, dao_factory)
  return Application.super.new(self, COLLECTION, SCHEMA, t, dao_factory)
end

function Application.find_one(args, dao_factory)
  local data, err =  Application.super._find_one(args, dao_factory[COLLECTION])
  if data then
    data = Application(data, dao_factory)
  end
  return data, err
end

function Application.find(args, page, size, dao_factory)
  local data, total, err = Application.super._find(args, page, size, dao_factory[COLLECTION])
  if data then
    for i,v in ipairs(data) do
      data[i] = Application(v, dao_factory)
    end
  end
  return data, total, err
end

-- TODO: When deleting an application, also delete all his plugins/metrics

return Application
