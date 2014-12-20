-- Copyright (C) Mashape, Inc.

local BaseModel = require "apenode.models.base_model"
local ApplicationModel = require "apenode.models.application"
local ApiModel = require "apenode.models.api"

local function check_application_id(application_id)
  if ApplicationModel.find_one({id = application_id}) then
    return true
  else
    return false, "Application not found"
  end
end

local function check_api_id(api_id)
  if ApiModel.find_one({id = api_id}) then
    return true
  else
    return false, "API not found"
  end
end

local COLLECTION = "plugins"
local SCHEMA = {
  id = { type = "string", read_only = true },
  api_id = { type = "string", required = true, func = check_api_id },
  application_id = { type = "string", required = false, func = check_application_id },
  name = { type = "string", required = true },
  value = { type = "table", required = true }
}

local Plugin = BaseModel:extend()
Plugin["_COLLECTION"] = COLLECTION
Plugin["_SCHEMA"] = SCHEMA

function Plugin:new(t)
  return Plugin.super:new(COLLECTION, SCHEMA, t)
end

function Plugin:save()
  if self.find_one({api_id = self.api_id, application_id = self.application_id, name = name }) then
    return nil, "The plugin already exist, update the current one"
  else
    return Plugin.super:save()
  end
end

function Plugin.find_one(args)
  return Plugin.super._find_one(COLLECTION, args)
end

function Plugin.find(args, page, size)
  return Plugin.super._find(COLLECTION, args, page, size)
end

function Plugin.find_and_delete(args)
  return Plugin.super._find_and_delete(COLLECTION, args)
end

return Plugin
