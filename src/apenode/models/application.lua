-- Copyright (C) Mashape, Inc.

local AccountModel = require "apenode.models.account"
local BaseModel = require "apenode.models.base_model"

local function check_account_id(account_id, t)
  if AccountModel.find_one({id = account_id}) then
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
  created_at = { type = "number", read_only = true, default = os.time() }
}

local Application = BaseModel:extend()
Application["_COLLECTION"] = COLLECTION
Application["_SCHEMA"] = SCHEMA

function Application:new(t)
  return Application.super.new(self, COLLECTION, SCHEMA, t)
end

function Application.find_one(args)
  return Application.super._find_one(COLLECTION, args)
end

function Application.find(args, page, size)
  return  Application.super._find(COLLECTION, args, page, size)
end

-- TODO: When deleting an application, also delete all his plugins/metrics

return Application
