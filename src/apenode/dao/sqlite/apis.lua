local stringy = require "stringy"
local BaseDao = require "apenode.dao.sqlite.base_dao"
local ApiModel = require "apenode.models.api"

local Apis = {}
Apis.__index = Apis

setmetatable(Apis, {
  __index = BaseDao,
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self.PUTAIN = "HELLO"
    self:_init(...)
    return self
  end
})

function Apis:_init(database)
  BaseDao._init(self, database, ApiModel._COLLECTION, ApiModel._SCHEMA)
end

-- @PRIVATE
local function serialize_api(api)
  if not api then return end

  local key_names = api.authentication_key_names
  if not key_names then key_names = {} end

  api.authentication_key_names = table.concat(key_names, ";")

  return api
end

local function deserialize_api(api)
  local key_names

  if api.authentication_key_names ~= nil and api.authentication_key_names ~= "" then
    key_names = stringy.split(api.authentication_key_names, ";")
  else
    key_names = {}
  end

  api.authentication_key_names = key_names

  return api
end

local function deserializer(api, err)
  if err or not api then return nil, err end
  return deserialize_api(api)
end

-- @PUBLIC

-- @override
function Apis:insert(api)
  local api, err = BaseDao.insert(self, serialize_api(api))
  if err then
    return nil, err
  elseif api then
    return deserialize_api(api)
  end
end

-- @override
function Apis:update(api, where_keys)
  local result, err = BaseDao.update(self, serialize_api(api), where_keys)
  if err then
    return nil, err
  elseif api then
    return result
  end
end

-- @override
function Apis:insert_or_update(api)
  local api, err = BaseDao.insert_or_update(self, serialize_api(api))
  if err then
    return nil, err
  elseif api then
    return deserialize_api(api)
  end
end

-- @override
function Apis:find_one(keys)
  return deserializer(BaseDao.find_one(self, keys))
end

-- @override
function Apis:find(where_keys, page, size)
  local results, count, err = BaseDao.find(self, where_keys, page, size)
  if err then
    return nil, nil, err
  end

  for _,api in ipairs(results) do
    api = deserialize_api(api)
  end

  return results, count
end

return Apis
