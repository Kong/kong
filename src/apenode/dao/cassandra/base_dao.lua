-- Copyright (C) Mashape, Inc.

local cassandra = require "cassandra"
local schemas = require "apenode.dao.schemas"
local stringy = require "stringy"
local Object = require "classic"
local utils = require "apenode.tools.utils"
local uuid = require "uuid"
local cjson = require "cjson"

local validate = schemas.validate

local BaseDao = Object:extend()

function BaseDao:new(database)
  -- This is important to seed the UUID generator
  uuid.seed()

  self._db = database
  self._statements = {} -- Mirror of _queries but with prepared statements instead of strings
  self._statements_cache = {} -- Prepared statements of SELECTS generated with find_by_keys
end

-- Prepare all statements in self._queries and put them in self._statements.
-- Should be called without parameters and will recursively call itself for nested statements.
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
        error("Failed to prepare statement: "..q..". Error: "..err)
      else
        statements[stmt_name] = {
          params = query.params,
          query = prepared_stmt
        }
      end
    end
  end
end

-- Run a statement and check if the result exists
--
-- @param {table} t Arguments to bind to the statement
-- @param {statement} statement Statement to execute
-- @param {boolean} is_updating is_updating If true, will ignore UNIQUE if same entity
-- @return {boolean} true if doesn't exist (UNIQUE), false otherwise
-- @return {string|nil} Error if any during execution
function BaseDao:check_unique(statement, t, is_updating)
  local results, err = self:execute_prepared_stmt(statement, t)
  if err then
    return false, "Error during UNIQUE check: "..err
  elseif results and #results > 0 then
    if not is_updating then
      return false
    else
      -- If we are updating, we ignore UNIQUE values if coming from the same entity
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

-- Run a statement and check if the results exists
--
-- @param {statement} statement Statement to execute
-- @param {table} t Arguments to bind to the statement
-- @return {boolean} true if EXISTS, false otherwise
-- @return {string|nil} Error if any during execution
-- @return {table|nil} Results of the statement if EXISTS
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

-- Run the EXISTS on all statements in __exists
--
-- @param {table} t Arguments to bind to the __exists statements
-- @return {boolean} true if all results EXIST, false otherwise
-- @return {table|nil} Error if any during execution
function BaseDao:check_all_exists(t)
  if not self._statements.__exists then return true end

  local errors
  for k, statement in pairs(self._statements.__exists) do
    if t[k] then
      local exists, err = self:check_exists(statement, t)
      if err then
        errors = utils.add_error(errors, k, err)
      elseif not exists then
        errors = utils.add_error(errors, k, k.." "..t[k].." does not exist")
      end
    end
  end

  return errors == nil, errors
end

-- Run the UNIQUE on all statements in __unique
--
-- @param {table} t Arguments to bind to the __unique statements
-- @param {boolean} is_updating is_updating If true, will ignore UNIQUE if same entity
-- @return {boolean} true if all results are UNIQUE, false otherwise
-- @return {table|nil} Error if any during execution
function BaseDao:check_all_unique(t, is_updating)
  if not self._statements.__unique then return true end

  local errors
  for k, statement in pairs(self._statements.__unique) do
    local unique, err = self:check_unique(statement, t, is_updating)
    if err then
      errors = utils.add_error(errors, k, err)
    elseif not unique then
      errors = utils.add_error(errors, k, k.." already exists with value "..t[k])
    end
  end

  return errors == nil, errors
end

-- Execute the prepared INSERT statement
-- Validate entity's schema + UNIQUE values + FOREIGN KEYS
-- Generates id and created_at fields
--
-- @param {table} t Entity to insert (binded to statement)
-- @return {table|nil} Inserted entity or nil
-- @return {table|nil} Error if any
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

  local _, err = self:execute_prepared_stmt(self._statements.insert, t)

  if err then
    return nil, err
  else
    return t
  end
end

-- Execute the prepared UPDATE statement
-- Validate entity's schema + UNIQUE values + FOREIGN KEYS
--
-- @param {table} t Entity to insert (binded to statement)
-- @return {table|nil} Updated entity or nil
-- @return {table|nil} Error if any
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
    -- @see https://issues.apache.org/jira/browse/CASSANDRA-7304
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

  local _, err = self:execute_prepared_stmt(self._statements.update, t)

  if err then
    return nil, err
  else
    return t
  end
end

-- Execute the prepared SELECT statement as it is
--
-- @return execute_prepared_stmt()
function BaseDao:find()
  return self:execute_prepared_stmt(self._statements.select)
end

-- Execute the prepared SELECT_ONE statement as it is
--
-- @param {string} id UUID of element to select
-- @return execute_prepared_stmt()
function BaseDao:find_one(id)
  return self:execute_prepared_stmt(self._statements.select_one, { id = id })
end

-- Execute a SELECT statement with special WHERE values
-- Build a new prepared statement and cache it for later use
--
-- @see _statements_cache
-- @warning Generated statement will use ALLOW FILTERING
--
-- @param {table} t Table from which the WHERE will be built, and the values will be binded
-- @return execute_prepared_stmt()
function BaseDao:find_by_keys(t)
  local where, keys, errors = {}, {}
  for k,v in pairs(t) do
    if self._schema[k].queryable or k == "id" then
      table.insert(where, string.format("%s = ?", k))
      table.insert(keys, k)
    else
      errors = utils.add_error(errors, k, k.." is not queryable.")
    end
  end

  if errors then
    return nil, errors
  end

  local where_str = "WHERE "..table.concat(where, " AND ")
  local select_query = string.format(self._queries.select.query, where_str.." ALLOW FILTERING")

  if not self._statements_cache[select_query] then
    local stmt, err = self._db:prepare(select_query)
    if err then
      return nil, err
    end

    self._statements_cache[select_query] = {
      query = stmt,
      params = keys
    }
  end

  return self:execute_prepared_stmt(self._statements_cache[select_query], t)
end

-- Execute the prepared DELETE statement
--
-- @param {string} id UUID of entity to delete
-- @return {boolean} True if deleted, false if otherwise or not found
-- @return {table|nil} Error if any
function BaseDao:delete(id)
  local exists, err = self:check_exists(self._statements.select_one, { id = id })
  if err then
    return false, err
  elseif not exists then
    return false, "Entity to delete not found"
  end

  return self:execute_prepared_stmt(self._statements.delete, { id = id })
end

---------------------
-- Cassandra UTILS --
---------------------

-- Build the list to pass to lua-resty-cassandra :execute method.
-- Since this method only accepts an ordered list, we build this list from
-- the `params` property of all prepared statement, taking into account special
-- cassandra values (uuid, timestamps, NULL)
--
-- @param {table} t Values to bind to a statement
-- @param {table} parameters An ordered list of parameters
-- @return {table} An ordered list of values to be binded to lua-resty-cassandra :execute
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

-- Execute a prepared statement
--
-- @param {table|statement} statement The prepared statement (cassandra or build by :prepare) to execute
-- @param {table} values_to_bind Raw values to bind
-- @return {table|boolean} Table if type of return is ROWS
--                         Boolean if type of results is VOID
-- @return {table|nil} Error if any
function BaseDao:execute_prepared_stmt(statement, values_to_bind)
  if statement.params and values_to_bind then
    values_to_bind = self:encode_cassandra_values(values_to_bind, statement.params)
  end

  local results, err = self._db:execute(statement.query, values_to_bind)

  if results and results.type == "ROWS" then
    -- erase this property to only return an ordered list
    results.type = nil

    -- return deserialized content for encoded values (plugins)
    if self._deserialize then
      for _,row in ipairs(results) do
        for k,v in pairs(row) do
          if self._schema[k].type == "table" then
            row[k] = cjson.decode(v)
          end
        end
      end
    end

    return results, err
  elseif results and results.type == "VOID" then
    -- return boolean
    return err == nil, err
  else
    return results, err
  end
end

return BaseDao
