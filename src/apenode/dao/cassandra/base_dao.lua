-- Copyright (C) Mashape, Inc.

local inspect = require "inspect"
local uuid = require "apenode.uuid"
local cassandra = require "apenode.dao.cassandra.cassandra"

local BaseDao = {}
BaseDao.__index = BaseDao

setmetatable(BaseDao, {
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

function BaseDao:query(cmd, args)
  local session = cassandra.new()

  session:set_timeout(configuration.dao.properties.timeout)

  local connected, err = session:connect(configuration.dao.properties.host, configuration.dao.properties.port)
  if not connected then
    ngx.log(ngx.ERR, "error: ", err)
    return
  end

  local ok, err = session:set_keyspace(configuration.dao.properties.keyspace)
  if not ok then
    ngx.log(ngx.ERR, "error: ", err)
    return
  end

  local result, err = session:execute(cmd, args)
  if err then
    ngx.log(ngx.ERR, "error: ", err)
    return
  end

  local ok, err = session:set_keepalive(configuration.dao.properties.keepalive)
  if not ok then
    ngx.log(ngx.ERR, "error: ", err)
    return
  end

  return result
end

function BaseDao:_init(collection)
  self._collection = collection
end

function BaseDao:save(entity)

  entity.id = uuid.generate()
  entity.created_at = os.time() * 1000
  entity.status = "ACTIVE"

  local cmd_field_values = {}
  local cmd_fields = ""
  local cmd_values = ""
  for k, v in pairs(entity) do
    cmd_fields = cmd_fields .. "," .. k
    cmd_values = cmd_values .. ",?"
    if type(v) == "table" then
      table.insert(cmd_field_values, cassandra.list(v))
    elseif k == "id" then
      table.insert(cmd_field_values, cassandra.uuid(v))
    elseif k == "created_at" then
      table.insert(cmd_field_values, cassandra.timestamp(v))
    else
      table.insert(cmd_field_values, v)
    end
  end
  cmd_fields = string.sub(cmd_fields, 2)
  cmd_values = string.sub(cmd_values, 2)

  local cmd = "INSERT INTO " .. self._collection .. " (" .. cmd_fields .. ") VALUES (" .. cmd_values .. ")"
  print(cmd)
  print(inspect(cmd_field_values))

  local res = self:query(cmd, cmd_field_values)
  print(inspect(res))
  return entity
end

function BaseDao:get_all(page, size)
  print(inspect(self:query("SELECT * from system.schema_keyspaces")))
  local result = {}
  return result, 0
end

function BaseDao:get_by_id(id)
  return nil
end

function BaseDao:delete(id)
  return {}
end

function BaseDao:update(entity)
  return entity
end

return BaseDao