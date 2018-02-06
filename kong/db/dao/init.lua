local cjson        = require "cjson"

local setmetatable = setmetatable
local tonumber     = tonumber
local require      = require
local error        = error
local pairs        = pairs
local type         = type
local min          = math.min
local log          = ngx.log


local ERR          = ngx.ERR


local new_tab
do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function() return {} end
  end
end


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

        if size ~= nil then
          if type(size) ~= "number" then
            error("size must be a number", 2)
          end

          if size < 0 then
            error("size must be a positive number", 2)
          end

          size = min(size, 1000)

        else
          size = 100
        end

        if offset ~= nil and type(offset) ~= "string" then
          error("offset must be a string", 2)
        end

        local ok, errors = self.schema:validate_primary_key(foreign_key)
        if not ok then
          local err_t = self.errors:invalid_primary_key(errors)
          return nil, tostring(err_t), err_t
        end

        local strategy = self.strategy

        local rows, err_t, new_offset = strategy[method_name](strategy,
                                                              foreign_key,
                                                              size, offset)
        if not rows then
          return nil, tostring(err_t), err_t
        end

        local entities, err, err_t = self:rows_to_entities(rows)
        if err then
          return nil, err, err_t
        end

        return entities, nil, nil, new_offset
      end

    elseif field.unique then
      local function validate_unique_value(unique_value)
        local ok, err = self.schema:validate_field(field, unique_value)
        if not ok then
          error("invalid argument '" .. name .. "' (" .. err .. ")", 3)
        end
      end

      self["select_by_" .. name] = function(self, unique_value)
        validate_unique_value(unique_value)

        local row, err_t = self.strategy:select_by_field(name, unique_value)
        if err_t then
          return nil, tostring(err_t), err_t
        end

        if not row then
          return nil
        end

        return self:row_to_entity(row)
      end

      self["update_by_" .. name] = function(self, unique_value, entity)
        validate_unique_value(unique_value)

        local entity_to_update, err = self.schema:process_auto_fields(entity, "update")
        if not entity_to_update then
          local err_t = self.errors:schema_violation(err)
          return nil, tostring(err_t), err_t
        end

        local ok, errors = self.schema:validate_update(entity_to_update)
        if not ok then
          local err_t = self.errors:schema_violation(errors)
          return nil, tostring(err_t), err_t
        end

        local row, err_t = self.strategy:update_by_field(name, unique_value,
                                                         entity_to_update)
        if not row then
          return nil, tostring(err_t), err_t
        end

        row, err, err_t = self:row_to_entity(row)
        if not row then
          return nil, err, err_t
        end

        self:post_crud_event("update", row)

        return row
      end

      self["delete_by_" .. name] = function(self, unique_value)
        validate_unique_value(unique_value)

        local _, err_t = self.strategy:delete_by_field(name, unique_value)
        if err_t then
          return nil, tostring(err_t), err_t
        end

        self:post_crud_event("delete")

        return true
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
    return nil, tostring(err_t), err_t
  end

  local row, err_t = self.strategy:select(primary_key)
  if err_t then
    return nil, tostring(err_t), err_t
  end

  if not row then
    return nil
  end

  return self:row_to_entity(row)
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

  local rows, err_t, offset = self.strategy:page(size, offset)
  if err_t then
    return nil, tostring(err_t), err_t
  end

  local entities, err, err_t = self:rows_to_entities(rows)
  if not entities then
    return nil, err, err_t
  end

  return entities, err, err_t, offset
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

  local next_row = self.strategy:each(size)

  return function()
    local err_t
    local row, err, page = next_row()
    if not row then
      if err then
        local err_t = self.errors:database_error(err)
        return nil, tostring(err_t), err_t
      end

      return nil
    end

    row, err, err_t = self:row_to_entity(row)
    if not row then
      return nil, err, err_t
    end

    return row, nil, page
  end
end


function DAO:insert(entity)
  if type(entity) ~= "table" then
    error("entity must be a table", 2)
  end

  local entity_to_insert, err = self.schema:process_auto_fields(entity, "insert")
  if not entity_to_insert then
    local err_t = self.errors:schema_violation(err)
    return nil, tostring(err_t), err_t
  end

  local ok, errors = self.schema:validate(entity_to_insert)
  if not ok then
    local err_t = self.errors:schema_violation(errors)
    return nil, tostring(err_t), err_t
  end

  local row, err_t = self.strategy:insert(entity_to_insert)
  if not row then
    return nil, tostring(err_t), err_t
  end

  row, err, err_t = self:row_to_entity(row)
  if not row then
    return nil, err, err_t
  end

  self:post_crud_event("create", row)

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
    return nil, tostring(err_t), err_t
  end

  local entity_to_update, err = self.schema:process_auto_fields(entity, "update")
  if not entity_to_update then
    local err_t = self.errors:schema_violation(err)
    return nil, tostring(err_t), err_t
  end

  local ok, errors = self.schema:validate_update(entity_to_update)
  if not ok then
    local err_t = self.errors:schema_violation(errors)
    return nil, tostring(err_t), err_t
  end

  local row, err_t = self.strategy:update(primary_key, entity_to_update)
  if not row then
    return nil, tostring(err_t), err_t
  end

  row, err, err_t = self:row_to_entity(row)
  if not row then
    return nil, err, err_t
  end

  self:post_crud_event("update", row)

  return row
end


function DAO:delete(primary_key)
  if type(primary_key) ~= "table" then
    error("primary_key must be a table", 2)
  end

  local ok, errors = self.schema:validate_primary_key(primary_key)
  if not ok then
    local err_t = self.errors:invalid_primary_key(errors)
    return nil, tostring(err_t), err_t
  end

  local _, err_t = self.strategy:delete(primary_key)
  if err_t then
    return nil, tostring(err_t), err_t
  end

  self:post_crud_event("delete")

  return true
end


function DAO:rows_to_entities(rows)
  local count = #rows
  if count == 0 then
    return setmetatable(rows, cjson.empty_array_mt)
  end

  local entities = new_tab(count, 0)

  for i = 1, count do
    local entity, err, err_t = self:row_to_entity(rows[i])
    if not entity then
      return nil, err, err_t
    end

    entities[i] = entity
  end

  return entities
end


function DAO:row_to_entity(row)
  local entity, errors = self.schema:process_auto_fields(row, "select")
  if not entity then
    local err_t = self.errors:schema_violation(errors)
    return nil, tostring(err_t), err_t
  end

  return entity
end


function DAO:post_crud_event(operation, entity)
  if self.events then
    local ok, err = self.events.post_local("dao:crud", operation, {
      operation = operation,
      schema    = self.schema,
      new_db    = true,
      entity    = entity,
    })
    if not ok then
      log(ERR, "[db] failed to propagate CRUD operation: ", err)
    end
  end

end


return _M
