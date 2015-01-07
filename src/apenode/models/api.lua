-- Copyright (C) Mashape, Inc.

local BaseModel = require "apenode.models.base_model"

local COLLECTION = "apis"
local SCHEMA = {
  id = { type = "string", read_only = true },
  name = { type = "string", required = true, unique = true },
  public_dns = { type = "string", required = true, unique = true, regex = "(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9])\\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\\-]*[A-Za-z0-9])" },
  target_url = { type = "string", required = true },
  created_at = { type = "number", read_only = true, default = os.time() }
}

local Api = BaseModel:extend()
Api["_COLLECTION"] = COLLECTION
Api["_SCHEMA"] = SCHEMA

function Api:new(t, dao_factory)
  return Api.super.new(self, COLLECTION, SCHEMA, t, dao_factory)
end

function Api.find_one(args, dao_factory)
  return Api.super._find_one(args, COLLECTION, dao_factory)
end

function Api.find(args, page, size, dao_factory)
  return Api.super._find(args, page, size, COLLECTION, dao_factory)
end

-- TODO: When deleting an API, also delete all his plugins/metrics

return Api
