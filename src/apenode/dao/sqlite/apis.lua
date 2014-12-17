local stringy = require "stringy"
local BaseDao = require "apenode.dao.sqlite.base_dao"
local ApiModel = require "apenode.models.api"

local Apis = {}
Apis.__index = Apis

setmetatable(Apis, {
  __index = BaseDao,
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end
})

function Apis:_init(database)
  BaseDao:_init(database)
  self._collection = ApiModel._COLLECTION

  self.update_stmt = database:prepare [[
    UPDATE apis
    SET name = :name,
        public_dns = :public_dns,
        target_url = :target_url,
        authentication_type = :authentication_type,
        authentication_key_names = :authentication_key_names
    WHERE id = :id;
  ]]

  self.delete_stmt = database:prepare [[
    DELETE FROM apis WHERE id = ?;
  ]]

  self.select_count_stmt = database:prepare [[
    SELECT COUNT(*) FROM apis;
  ]]

  self.select_all_stmt = database:prepare [[
    SELECT * FROM apis LIMIT :page, :size;
  ]]

  self.select_by_id_stmt = database:prepare [[
    SELECT * FROM apis WHERE id = ?;
  ]]

  self.select_by_host_stmt = database:prepare [[
    SELECT * FROM apis WHERE public_dns = ?;
  ]]
end

-- @PRIVATE
local function serialize_api(api)
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
function Apis:save(api)
  local api, err = BaseDao.save(self, serialize_api(api))
  if err then
    return nil, err
  end

  return deserialize_api(api)
end

-- @override
function Apis:update(keys, api)
  local rowid, err = BaseDao.update(self, keys, serialize_api(api))
  if err then
    return nil, err
  end

  return deserialize_api(api)
end

-- @override
function Apis:get_by_id(id)
  return deserializer(BaseDao.get_by_id(self, id))
end

-- @override
function Apis:get_all(page, size)
  local results, count, err = BaseDao.get_all(self, page, size)
  if err then
    return nil, nil, err
  end

  for _,api in ipairs(results) do
    api = deserialize_api(api)
  end

  return results, count
end

function Apis:get_by_host(public_dns)
  self.select_by_host_stmt:bind_values(public_dns)
  return deserializer(self:exec_select_stmt(self.select_by_host_stmt))
end

return Apis
