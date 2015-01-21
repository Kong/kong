-- Copyright (C) Mashape, Inc.

local ApplicationModel = require "apenode.models.application"
local BaseModel = require "apenode.models.base_model"
local ApiModel = require "apenode.models.api"
local utils = require "apenode.tools.utils"

local function check_application_id(application_id, t, dao_factory)
  if not application_id or ApplicationModel.find_one({id = application_id}, dao_factory) then
    return true
  else
    return false, "Application not found"
  end
end

local function check_api_id(api_id, t, dao_factory)
  if ApiModel.find_one({id = api_id}, dao_factory) then
    return true
  else
    return false, "API not found"
  end
end

local function get_schema(object)
  local status, plugin = pcall(require, "apenode.plugins."..object.name..".handler")
  if not status then
    return false, "Plugin \""..object.name.."\" not found"
  end

  return plugin._SCHEMA
end

local COLLECTION = "plugins"
local SCHEMA = {
  id = { type = "id", read_only = true },
  api_id = { type = "id", required = true, func = check_api_id },
  application_id = { type = "id", required = false, func = check_application_id },
  name = { type = "string", required = true },
  value = { type = "table", required = true, schema_from_func = get_schema },
  created_at = { type = "timestamp", read_only = false, default = utils.get_utc }
}

local Plugin = BaseModel:extend()
Plugin["_COLLECTION"] = COLLECTION
Plugin["_SCHEMA"] = SCHEMA

function Plugin:new(t, dao_factory)
  return Plugin.super.new(self, COLLECTION, SCHEMA, t, dao_factory)
end

function Plugin:save()
  local res, err = self:_validate(self._schema, self._t, false)
  if not err then
    if self.find_one({api_id = self.api_id, application_id = self.application_id, name = self.name }, self._dao_factory) then
      return nil, "The plugin already exists, updating the current one."
    else
      return Plugin.super.save(self)
    end
  end
  return res, err
end

function Plugin.find_one(args, dao_factory)
  local data, err =  Plugin.super._find_one(args, dao_factory[COLLECTION])
  if data then
    data = Plugin(data, dao_factory)
  end
  return data, err
end

function Plugin.find(args, page, size, dao_factory)
  local data, total, err = Plugin.super._find(args, page, size, dao_factory[COLLECTION])
  if data then
    for i,v in ipairs(data) do
      data[i] = Plugin(v, dao_factory)
    end
  end
  return data, total, err
end

return Plugin
