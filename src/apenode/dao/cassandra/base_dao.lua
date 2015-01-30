-- Copyright (C) Mashape, Inc.

local cassandra = require "cassandra"
local schemas = require "apenode.dao.schemas"
local stringy = require "stringy"
local Object = require "classic"
local utils = require "apenode.tools.utils"
local uuid = require "uuid"
local cjson = require "cjson"

local validate = schemas.validate

-- This is important to seed the UUID generator
uuid.seed()

local BaseDao = Object:extend()

function BaseDao:new(database)
  self._db = database
  self._statements = {}
end

function BaseDao:prepare(queries, statements)
  if not queries then queries = self._queries end
  if not statements then statements = self._statements end

  for stmt_name, query in pairs(queries) do
    if type(query) == "table" and query.query == nil then
      self._statements[stmt_name] = {}
      self:prepare(query, self._statements[stmt_name])
    else
      local prepared_stmt, err = self._db:prepare(stringy.strip(query.query))
      if err then
        error("Failed to prepare statement: "..err)
      else
        statements[stmt_name] = {
          params = query.params,
          query = prepared_stmt
        }
      end
    end
  end
end

function BaseDao:check_unique(t, statement)
  local results, err = self:execute_prepared_stmt(t, statement)
  if err then
    return false, "Error during UNIQUE check: "..err
  elseif results and #results > 0 then
    return false
  else
    return true
  end
end

function BaseDao:check_exists(t, statement)
  local results, err = self:execute_prepared_stmt(t, statement)
  if err then
    return false, "Error during EXISTS check: "..err
  elseif not results or #results == 0 then
    return false
  else
    return true
  end
end

function BaseDao:check_all_exists(t)
  if not self._statements.exists then return true end

  local errors
  for k, statement in pairs(self._statements.exists) do
    if t[k] then
      local exists, err = self:check_exists(t, statement)
      if err then
        errors = schemas.add_error(errors, k, err)
      elseif not exists then
        errors = schemas.add_error(errors, k, k.." "..t[k].." does not exist")
      end
    end
  end

  return errors == nil, errors
end

function BaseDao:check_all_unique(t)
  if not self._statements.unique then return true end

  local errors
  for k, statement in pairs(self._statements.unique) do
    local unique, err = self:check_unique(t, statement)
    if err then
      errors = schemas.add_error(errors, k, err)
    elseif not unique then
      errors = schemas.add_error(errors, k, k.." already exists with value "..t[k])
    end
  end

  return errors == nil, errors
end

function BaseDao:insert(t, statement)
  if not t then return nil, "Cannot insert a nil element" end

  -- Override created_at by default value
  t.created_at = utils.get_utc() * 1000

  -- Validate schema
  local valid_schema, errors = validate(t, self._schema)
  if not valid_schema then
    return nil, errors
  end

  local unique, errors = self:check_all_unique(t)
  if not unique then
    return nil, errors
  end

  local exists, errors = self:check_all_exists(t)
  if not exists then
    return nil, errors
  end

  local insert_statement
  if statement then
    insert_statement = statement
  else
    insert_statement = self._statements.insert
  end

  local success, err = self:execute_prepared_stmt(t, insert_statement)

  if not success then
    return nil, err
  else
    return t
  end
end

function BaseDao:update(t)

end

---------------------
-- Cassandra UTILS --
---------------------

function BaseDao:encode_cassandra_values(t, parameters)
  local values_to_bind = {}
  for _, column in ipairs(parameters) do
    local schema_field = self._schema[column]
    local value = t[column]

    if schema_field.type == "id" then
      if column == "id" then
        -- If it is the inserted entity's id, we generate it
        -- and attach it to the table for return value
        t[column] = uuid()
        value = t[column]
      end
      if value then
        value = cassandra.uuid(value)
      else
        value = cassandra.null
      end
    elseif schema_field.type == "timestamp" then
      value = cassandra.timestamp(value)
    elseif schema_field.type == "table" and value then
      value = cjson.encode(value)
    end

    table.insert(values_to_bind, value)
  end

  return values_to_bind
end

function BaseDao:execute_prepared_stmt(t, statement)
  local values_to_bind = self:encode_cassandra_values(t, statement.params)
  return self._db:execute(statement.query, values_to_bind)
end

return BaseDao
