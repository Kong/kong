local cjson        = require "cjson"

local setmetatable = setmetatable
local tonumber     = tonumber
local require      = require
local error        = error
local pairs        = pairs
local type         = type
local min          = math.min


local _M    = {}
local DAO   = {}
DAO.__index = DAO


local function generate_foreign_key_methods(self)
  local schema = self.schema

  for name, field in schema:each_field() do
    if field.type == "foreign" then
      local method_name = "for_" .. name
      self[method_name] = function(self, foreign_key, size, offset)
        if type(foreign_key) ~= "table" then
          error("foreign_key must be a table", 2)
        end

        local ok, errors = field.schema:validate_primary_key(foreign_key)
        if not ok then
          local err_t = self.errors:invalid_primary_key(errors)
          return nil, err_t.name, err_t
        end

        size = tonumber(size == nil and 100 or size)

        if not size then
          error("size must be a number", 2)
        end

        size = min(size, 1000)

        if size < 0 then
          error("size must be positive (> 0)", 2)
        end

        if offset ~= nil and type(offset) ~= "string" then
          error("offset must be a string", 2)
        end

        local rows, err_t, new_offset = self.strategy[method_name](self.strategy, foreign_key, size, offset)
        if err_t then
          return nil, err_t.name, err_t
        end

        return rows, nil, nil, new_offset
      end
    end
  end
end


function _M.new(schema, strategy, errors)
  local self = {
    schema   = schema,
    strategy = strategy,
    errors   = errors,
  }

  if schema.dao then
    local custom_dao = require(schema.dao)
    for name, method in pairs(custom_dao) do
      self[name] = method
    end
  end

  generate_foreign_key_methods(self)

  return setmetatable(self, DAO)
end


function DAO:select(primary_key)
  if type(primary_key) ~= "table" then
    error("primary_key must be a table", 2)
  end

  local ok, errors = self.schema:validate_primary_key(primary_key)
  if not ok then
    local err_t = self.errors:invalid_primary_key(errors)
    return nil, err_t.name, err_t
  end

  local row, err_t = self.strategy:select(primary_key)
  if err_t then
    return nil, err_t.name, err_t
  end

  return row
end


function DAO:page(size, offset)
  size = tonumber(size == nil and 100 or size)

  if not size then
    error("size must be a number", 2)
  end

  size = min(size, 1000)

  if size < 0 then
    error("size must be positive (> 0)", 2)
  end

  if offset ~= nil and type(offset) ~= "string" then
    error("offset must be a string", 2)
  end

  local rows, err_t, new_offset = self.strategy:page(size, offset)
  if err_t then
    return nil, err_t.name, err_t
  end

  setmetatable(rows, cjson.empty_array_mt)

  return rows, nil, nil, new_offset
end


function DAO:each(size)
  size = tonumber(size == nil and 100 or size)

  if not size then
    error("size must be a number", 2)
  end

  size = min(size, 1000)

  if size < 0 then
    error("size must be positive (> 0)", 2)
  end

  return self.strategy:each(size)
end


function DAO:insert(entity)
  if type(entity) ~= "table" then
    error("entity must be a table", 2)
  end

  local entity_to_insert, errors = self.schema:process_auto_fields(entity,
                                                                   "insert")
  if not entity_to_insert then
    local err_t = self.errors:schema_violation(errors)
    return nil, err_t.name, err_t
  end

  local ok, errors = self.schema:validate(entity_to_insert)
  if not ok then
    local err_t = self.errors:schema_violation(errors)
    return nil, err_t.name, err_t
  end

  local row, err_t = self.strategy:insert(entity_to_insert)
  if not row then
    return nil, err_t.name, err_t
  end

  return row
end


function DAO:update(primary_key, entity)
  if type(primary_key) ~= "table" then
    error("primary_key must be a table", 2)
  end

  if type(entity) ~= "table" then
    error("entity must be a table", 2)
  end

  local ok, errors = self.schema:validate_primary_key(primary_key)
  if not ok then
    local err_t = self.errors:invalid_primary_key(errors)
    return nil, err_t.name, err_t
  end

  local entity_to_insert = self.schema:process_auto_fields(entity, "update")

  ok, errors = self.schema:validate_update(entity_to_insert)
  if not ok then
    local err_t = self.errors:schema_violation(errors)
    return nil, err_t.name, err_t
  end

  local row, err_t = self.strategy:update(primary_key, entity)
  if not row then
    return nil, err_t.name, err_t
  end

  return row
end


function DAO:delete(primary_key)
  if type(primary_key) ~= "table" then
    error("primary_key must be a table", 2)
  end

  local ok, errors = self.schema:validate_primary_key(primary_key)
  if not ok then
    local err_t = self.errors:invalid_primary_key(errors)
    return nil, err_t.name, err_t
  end

  local _, err_t = self.strategy:delete(primary_key)
  if err_t then
    return nil, err_t.name, err_t
  end

  return true
end


return _M
