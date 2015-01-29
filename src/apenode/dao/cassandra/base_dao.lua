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
    if type(query) == "table" then
      self._statements[stmt_name] = {}
      self:prepare(query, self._statements[stmt_name])
    else
      local prepared_stmt, err = self._db:prepare(stringy.strip(query))
      if err then
        error("Failed to prepare statement: "..err)
      else
        statements[stmt_name] = prepared_stmt
      end
    end
  end
end

function BaseDao:insert(t)
  if not t then return nil, "Cannot insert a nil element" end

  -- Override id and created_at by default values
  t.id = uuid()
  t.created_at = utils.get_utc() * 1000

  -- Validate schema
  local valid, errors = validate(t, self._schema)
  if not valid then
    return nil, errors
  end

  -- Build values to bind in order of the schema and query placeholders
  local values_to_bind = {}
  for _, schema_field in ipairs(self._schema) do
    local column = schema_field._
    local value = t[column]

    if schema_field.type == "id" then
      value = cassandra.uuid(value)
    elseif schema_field.type == "timestamp" then
      value = cassandra.timestamp(value)
    elseif schema_field.type == "table" and value then
      value = cjson.encode(value)
    end

    if schema_field.exists then
      local results, err = self:_exec_stmt(self._statements.exists[column], {value})
      if err then
        return nil, "Error during EXISTS check: "..err
      elseif not results or #results == 0 then
        return nil, "Exists check failed on field: "..column.." with value: "..t[column]
      end
    end

    if schema_field.unique then
      local results, err = self:_exec_stmt(self._statements.unique[column], {value})
      if err then
        return nil, "Error during UNIQUE check: "..err
      elseif results and #results > 0 then
        return nil, "Unique check failed on field: "..column.." with value: "..t[column]
      end
    end

    table.insert(values_to_bind, value)
  end

  local success, err = self:_exec_stmt(self._statements.insert, values_to_bind)
  if not success then
    return nil, err
  else
    return t
  end
end

---------------------
-- Cassandra UTILS --
---------------------

-- Execute prepared statement.
--
-- @param {table} statement A prepared statement
-- @param {table} values Values to bind to the statement
-- @return {boolean} Success of the query
-- @return {table} Error
function BaseDao:_exec_stmt(statement, values)
  return self._db:execute(statement, values)
end

return BaseDao
