-- Copyright (C) Mashape, Inc.

local utils = require "apenode.tools.utils"
local BaseModel = require "apenode.models.base_model"

local COLLECTION = "apis"
local SCHEMA = {
  id = { type = "string", read_only = true },
  name = { type = "string", required = true, unique = true },
  public_dns = { type = "string", required = true, unique = true, regex = "(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9])\\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\\-]*[A-Za-z0-9])" },
  target_url = { type = "string", required = true },
  created_at = { type = "number", read_only = true, default = utils.get_utc() }
}

local Api = BaseModel:extend()
Api["_COLLECTION"] = COLLECTION
Api["_SCHEMA"] = SCHEMA

function Api:new(t, dao_factory)
  return Api.super.new(self, COLLECTION, SCHEMA, t, dao_factory)
end

function Api.find_one(args, dao_factory)
  local data, err =  Api.super._find_one(args, dao_factory[COLLECTION])
  if data then
    data = Api(data, dao_factory)
  end
  return data, err
end

function Api.find(args, page, size, dao_factory)
  local data, total, err = Api.super._find(args, page, size, dao_factory[COLLECTION])
  if data then
    for i,v in ipairs(data) do
      data[i] = Api(v, dao_factory)
    end
  end
  return data, total, err
end

function Api.delete_by_id(id, dao_factory)
  return Api.super._delete_by_id(id, dao_factory[COLLECTION])
end

function Api.update(entity, dao_factory)
  return Api.super._update(entity, dao_factory[COLLECTION])
end

-- TODO: When deleting an API, also delete all his plugins/metrics

return Api
