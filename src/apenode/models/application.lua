-- Copyright (C) Mashape, Inc.

local AccountModel = require "apenode.models.account"
local BaseModel = require "apenode.models.base_model"

local function check_account_id(account_id)
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

local Application = {
  _COLLECTION = COLLECTION,
  _SCHEMA = SCHEMA
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
  return BaseModel:_init(COLLECTION, t, SCHEMA)
end

function Application.find_one(args)
  return BaseModel._find_one(COLLECTION, args)
end

function Application.find(args, page, size)
  return BaseModel._find(COLLECTION, args, page, size)
end

function Application.find_and_delete(args)
  return BaseModel._find_and_delete(COLLECTION, args)
end

-- TODO: When deleting an application, also delete all his plugins/metrics

return Application
