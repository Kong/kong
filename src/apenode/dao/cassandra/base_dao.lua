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
  self._select_statements_cache = {}
end

function BaseDao:prepare(queries, statements)
  if not queries then queries = self._queries end
  if not statements then statements = self._statements end

  for stmt_name, query in pairs(queries) do
    if type(query) == "table" and query.query == nil then
      self._statements[stmt_name] = {}
      self:prepare(query, self._statements[stmt_name])
    else
      local q = stringy.strip(query.query)
      q = string.format(q, "")
      local prepared_stmt, err = self._db:prepare(q)
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

function BaseDao:check_unique(t, statement, is_updating)
  local results, err = self:execute_prepared_stmt(statement, t)
  if err then
    return false, "Error during UNIQUE check: "..err
  elseif results and #results > 0 then
    if not is_updating then
      return false
    else
      -- If we are updating, we ignore UNIQUE values if
      -- coming from the same entity
      local unique = true
      for k,v in ipairs(results) do
        if v.id ~= t.id then
          unique = false
        end
      end

      return unique
    end
  else
    return true
  end
end

function BaseDao:check_exists(statement, t)
  local results, err = self:execute_prepared_stmt(statement, t)
  if err then
    return false, "Error during EXISTS check: "..err
  elseif not results or #results == 0 then
    return false
  else
    return true, nil, results
  end
end

function BaseDao:check_all_exists(t)
  if not self._statements.__exists then return true end

  local errors
  for k, statement in pairs(self._statements.__exists) do
    if t[k] then
      local exists, err = self:check_exists(statement, t)
      if err then
        errors = schemas.add_error(errors, k, err)
      elseif not exists then
        errors = schemas.add_error(errors, k, k.." "..t[k].." does not exist")
      end
    end
  end

  return errors == nil, errors
end

function BaseDao:check_all_unique(t, is_updating)
  if not self._statements.__unique then return true end

  local errors
  for k, statement in pairs(self._statements.__unique) do
    local unique, err = self:check_unique(t, statement, is_updating)
    if err then
      errors = schemas.add_error(errors, k, err)
    elseif not unique then
      errors = schemas.add_error(errors, k, k.." already exists with value "..t[k])
    end
  end

  return errors == nil, errors
end

function BaseDao:insert(t)
  if not t then return nil, "Cannot insert a nil element" end

  -- Override created_at and id by default value
  t.created_at = utils.get_utc() * 1000
  t.id = uuid()

  -- Validate schema
  local valid_schema, errors = validate(t, self._schema)
  if not valid_schema then
    return nil, errors
  end

  -- Check UNIQUE values
  local unique, errors = self:check_all_unique(t)
  if not unique then
    return nil, errors
  end

  -- Check foreign entities EXIST
  local exists, errors = self:check_all_exists(t)
  if not exists then
    return nil, errors
  end

  local success, err = self:execute_prepared_stmt(self._statements.insert, t)

  if not success then
    return nil, err
  else
    return t
  end
end

function BaseDao:update(t)
  if not t then return nil, "Cannot update a nil element" end

  -- Check if exists to prevent upsert
  -- and set UNSET values
  -- (pfffff...)
  local exists, err, results = self:check_exists(self._statements.select_one, t)
  if err then
    return nil, err
  elseif not exists then
    return nil, "Entity to update not found"
  else
    -- Set UNSET values to prevent cassandra from setting to NULL
    -- @see Test case
    -- https://issues.apache.org/jira/browse/CASSANDRA-7304
    for k,v in pairs(results[1]) do
      if not t[k] then
        t[k] = v
      end
    end
  end

  -- Validate schema
  local valid_schema, errors = validate(t, self._schema)
  if not valid_schema then
    return nil, errors
  end

  -- Check UNIQUE with update
  local unique, errors = self:check_all_unique(t, true)
  if not unique then
    return nil, errors
  end

  -- Check foreign entities EXIST
  local exists, errors = self:check_all_exists(t)
  if not exists then
    return nil, errors
  end

  local success, err = self:execute_prepared_stmt(self._statements.update, t)

  if not success then
    return nil, err
  else
    return t
  end
end

function BaseDao:find()
  return self:execute_prepared_stmt(self._statements.select)
end

function BaseDao:find_one(id)
  return self:execute_prepared_stmt(self._statements.select_one, { id = id })
end

function BaseDao:find_by_keys(t)
  local where, keys = {}, {}
  for k,v in pairs(t) do
    table.insert(where, string.format("%s = ?", k))
    table.insert(keys, k)
  end

  local where_str = "WHERE "..table.concat(where, " AND ")
  local select_query = string.format(self._queries.select.query, where_str.." ALLOW FILTERING")

  local stmt = self._select_statements_cache[select_query]

  if not stmt then
    local prepared_stmt, err = self._db:prepare(select_query)
    if err then
      return nil, err
    end

    stmt = {
      query = prepared_stmt,
      params = keys
    }
    
    self._select_statements_cache[select_query] = stmt
  end

  return self:execute_prepared_stmt(stmt, t)
end

function BaseDao:delete(id)
  local exists, err = self:check_exists(self._statements.select_one, { id = id })
  if err then
    return nil, err
  elseif not exists then
    return nil, "Entity to delete not found"
  end

  return self:execute_prepared_stmt(self._statements.delete, { id = id })
end

---------------------
-- Cassandra UTILS --
---------------------

function BaseDao:encode_cassandra_values(t, parameters)
  local values_to_bind = {}
  for _, column in ipairs(parameters) do
    local schema_field = self._schema[column]
    local value = t[column]

    if schema_field.type == "id" and value then
      value = cassandra.uuid(value)
    elseif schema_field.type == "timestamp" and value then
      value = cassandra.timestamp(value)
    elseif schema_field.type == "table" and value then
      value = cjson.encode(value)
    elseif not value then
      value = cassandra.null
    end

    table.insert(values_to_bind, value)
  end

  return values_to_bind
end

function BaseDao:execute_prepared_stmt(statement, values_to_bind)
  if statement.params and values_to_bind then
    values_to_bind = self:encode_cassandra_values(values_to_bind, statement.params)
  end

  return self._db:execute(statement.query, values_to_bind)
end

return BaseDao
