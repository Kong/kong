-- Copyright (C) Mashape, Inc.

local BaseModel = require "apenode.models.base_model"

local COLLECTION = "apis"
local SCHEMA = {
  id = { type = "string", read_only = true },
  name = { type = "string", required = true, unique = true },
  public_dns = { type = "string", required = true, unique = true, regex = "(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9])\\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\\-]*[A-Za-z0-9])" },
  target_url = { type = "string", required = true },
  authentication_type = { type = "string", required = true },
  authentication_key_names = { type = "table", required = false },
  created_at = { type = "number", read_only = true, default = os.time() }
}

local Api = BaseModel:extend()
Api["_COLLECTION"] = COLLECTION
Api["_SCHEMA"] = SCHEMA

function Api:new(t)
  return Api.super.new(self, COLLECTION, SCHEMA, t)
end

function Api.find_one(args)
  return Api.super._find_one(COLLECTION, args)
end

function Api.find(args, page, size)
  return Api.super._find(COLLECTION, args, page, size)
end

function Api.find_and_delete(args)
  return Api.super._find_and_delete(COLLECTION, args)
end

-- TODO: When deleting an API, also delete all his plugins/metrics

return Api
