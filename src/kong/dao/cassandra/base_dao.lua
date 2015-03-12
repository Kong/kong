local cassandra = require "cassandra"
local Object = require "classic"
local uuid = require "uuid"
local rex = require "rex_pcre"

local constants = require "kong.constants"
local validate = require("kong.dao.schemas").validate
local utils = require "kong.tools.utils"
local timestamp = require "kong.tools.timestamp"

local error_types = constants.DATABASE_ERROR_TYPES

local BaseDao = Object:extend()

-- This is important to seed the UUID generator
uuid.seed()

function BaseDao:new(properties)
  self._properties = properties
  self._statements = {} -- Mirror of _queries but with prepared statements instead of strings
  self._statements_cache = {} -- Prepared statements of SELECTS generated with find_by_keys
end

-------------
-- PRIVATE --
-------------

local pattern = "^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$"
local function is_valid_uuid(uuid)
  return rex.match(uuid, pattern) ~= nil
end

-- Build the list to pass to lua-resty-cassandra :execute method.
-- Since this method only accepts an ordered list, we build this list from
-- the `params` property of all prepared statement, taking into account special
-- cassandra values (uuid, timestamps, NULL)
-- @param {table} schema A schema with type properties to encode specific values
-- @param {table} t Values to bind to a statement
-- @param {table} parameters An ordered list of parameters
-- @return {table} An ordered list of values to be binded to lua-resty-cassandra :execute
-- @return {table} Error Cassandra type valdiation errors
local function encode_cassandra_values(schema, t, parameters)
  local values_to_bind = {}
  local errors
  for _, column in ipairs(parameters) do
    local schema_field = schema[column]
    local value = t[column]

    if schema_field.type == "id" and value then
      if is_valid_uuid(value) then
        value = cassandra.uuid(value)
      else
        errors = utils.add_error(errors, column, value.." is an invalid uuid")
      end
    elseif schema_field.type == "timestamp" and value then
      value = cassandra.timestamp(value)
    elseif value == nil then
      value = cassandra.null
    end

    table.insert(values_to_bind, value)
  end

  return values_to_bind, errors
end

-- Create a DAO error with type as boolan for fast comparison
function BaseDao:_build_error(type, err)
  if not err then
    return nil
  end

  return {
    [type] = true,
    message = err
  }
end

-- Marshall an entity. Does nothing by default,
-- must be overriden for entities where marshalling applies.
function BaseDao:_marshall(t)
  return t
end

-- Unmarshall an entity. Does nothing by default,
-- must be overriden for entities where marshalling applies.
function BaseDao:_unmarshall(t)
  return t
end

-- Run a statement and check if the result exists
--
-- @param {table} t Arguments to bind to the statement
-- @param {statement} statement Statement to execute
-- @param {boolean} is_updating is_updating If true, will ignore UNIQUE if same entity
-- @return {boolean} true if doesn't exist (UNIQUE), false otherwise
-- @return {string|nil} Error if any during execution
function BaseDao:_check_unique(statement, t, is_updating)
  local results, err = self:_execute(statement, t)
  if err then
    return false, "Error during UNIQUE check: "..err.message
  elseif results and #results > 0 then
    if not is_updating then
      return false
    else
      -- If we are updating, we ignore UNIQUE values if coming from the same entity
      local unique = true
      for k,v in ipairs(results) do
        if v.id ~= t.id then
          unique = false
          break
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
-- @return {boolean} true if FOREIGN exists, false otherwise
-- @return {string|nil} Error if any during execution
-- @return {table|nil} Results of the statement if FOREIGN
function BaseDao:_check_foreign(statement, t)
  local results, err = self:_execute(statement, t)
  if err then
    return false, "Error during FOREIGN check: "..err.message
  elseif not results or #results == 0 then
    return false
  else
    return true, nil, results
  end
end

-- Run the FOREIGN exists check on all statements in __foreign
--
-- @param {table} t Arguments to bind to the __foreign statements
-- @return {boolean} true if all results EXIST, false otherwise
-- @return {table|nil} Error if any during execution
-- @return {table|nil} A table with the list of not existing foreign entities
function BaseDao:_check_all_foreign(t)
  if not self._statements.__foreign then return true end

  local errors
  for k, statement in pairs(self._statements.__foreign) do
    if t[k] and t[k] ~= constants.DATABASE_NULL_ID then
      local exists, err = self:_check_foreign(statement, t)
      if err then
        return false, err
      elseif not exists then
        errors = utils.add_error(errors, k, k.." "..t[k].." does not exist")
      end
    end
  end

  return errors == nil, nil, errors
end

-- Run the UNIQUE on all statements in __unique
--
-- @param {table} t Arguments to bind to the __unique statements
-- @param {boolean} is_updating is_updating If true, will ignore UNIQUE if same entity
-- @return {boolean} true if all results are UNIQUE, false otherwise
-- @return {table|nil} Error if any during execution
-- @return {table|nil} A table with the list of already existing entities
function BaseDao:_check_all_unique(t, is_updating)
  if not self._statements.__unique then return true end

  local errors
  for k, statement in pairs(self._statements.__unique) do
    if t[k] or k == "self" then
      local unique, err = self:_check_unique(statement, t, is_updating)
      if err then
        return false, err
      elseif not unique and k == "self" then
        return false, nil, self._entity.." already exists"
      elseif not unique then
        errors = utils.add_error(errors, k, k.." already exists with value "..t[k])
      end
    end
  end

  return errors == nil, nil, errors
end

-- Open a Cassandra session on configured keyspace
-- @return session
-- @return Error if any
function BaseDao:_open_session()
  local ok, err

  -- Start cassandra session
  local session = cassandra.new()
  session:set_timeout(self._properties.timeout)

  ok, err = session:connect(self._properties.hosts, self._properties.port)
  if not ok then
    return nil, self:_build_error(error_types.DATABASE, err)
  end

  ok, err = session:set_keyspace(self._properties.keyspace)
  if not ok then
    return nil, self:_build_error(error_types.DATABASE, err)
  end

  return session
end

-- Close the given opened session. Will try to put the session in the socket pool if supported
-- @param session Cassandra session to close
-- @return Error if any
function BaseDao:_close_session(session)
  -- Back to the pool or close if using luasocket
  local ok, err = session:set_keepalive()
  if not ok and err == "luasocket does not support reusable sockets" then
    ok, err = session:close()
  end

  if not ok then
    return self:_build_error(error_types.DATABASE, err)
  end
end

-- Execute an operation statement.
--
-- # The operation can be one of the following:
--   * _statements (which contains .query and .param for ordered binding of parameters)
--   * a lua-resty-cassandra BatchStatement (see metrics.lua)
--   * a lua-resty-cassandra prepared statement
--
-- @param {table} operation The operation to execute
-- @param {table} values_to_bind Raw values to bind
-- @param {table} options Options to pass to lua-resty-cassandra :execute()
--                        page_size
--                        paging_state
-- @return {table|boolean} Table if type of return is ROWS
--                         Boolean if type of results is VOID
-- @return {table|nil} Cassandra error if any
function BaseDao:_execute(operation, values_to_bind, options)
  local statement

  -- Determine kind of operation
  if operation.is_kong_statement then
    statement = operation.query

    if operation.params and values_to_bind then
      local errors
      values_to_bind, errors = encode_cassandra_values(self._schema, values_to_bind, operation.params)
      if errors then
        return nil, self:_build_error(error_types.INVALID_TYPE, errors)
      end
    end
  elseif operation.is_batch_statement then
    statement = operation
    values_to_bind = nil
    options = nil
  else
    statement = operation
  end

  local session, err = self:_open_session()
  if err then
    return nil, err
  end

  -- Execute operation
  local results, err = session:execute(statement, values_to_bind, options)
  if err then
    err = self:_build_error(error_types.DATABASE, err)
  end

  local socket_err = self:_close_session(session)
  if socket_err then
    return nil, socket_err
  end

  -- Parse result
  if results and results.type == "ROWS" then
    -- do we have more pages to fetch?
    if results.meta.has_more_pages then
      results.next_page = results.meta.paging_state
    end

    results.meta = nil
    results.type = nil

    for i, row in ipairs(results) do
      results[i] = self:_unmarshall(row)
    end

    return results, err
  elseif results and results.type == "VOID" then
    -- return boolean
    return err == nil, err
  else
    return results, err
  end
end

----------------------
-- PUBLIC INTERFACE --
----------------------

-- Prepare a statement used by kong.
-- Since lua-resty-cassandra doesn't support binding by name yet, we need
-- to keep a record of properties to bind for each statement. Thus, a "kong statement"
-- is an object made of a prepared statement and an array of columns to bind.
-- See :_execute for the usage of this params array doing the binding.
--
-- @param {string} query A CQL query to prepare
-- @param {table} params An array of parameters (ordered) matching the query placeholders order
-- @return {table|nil} A "kong statement" to be used by _execute
-- @return {table|nil} Error if any
function BaseDao:prepare_kong_statement(query, params)
  local session, err = self:_open_session()
  if err then
    return nil, err
  end

  local prepared_stmt, prepare_err = session:prepare(query)

  local err = self:_close_session(session)
  if err then
    return nil, err
  end

  if prepare_err then
    return nil, "Failed to prepare statement: "..query..". Error: "..prepare_err
  else
    return {
      is_kong_statement = true,
      params = params,
      query = prepared_stmt
    }
  end
end


-- Execute the prepared INSERT statement
-- Validate entity's schema + UNIQUE values + FOREIGN KEYS
-- Generates id and created_at fields
--
-- @param {table} t Entity to insert (binded to statement)
-- @return {table|nil} Inserted entity or nil
-- @return {table|nil} Error if any
function BaseDao:insert(t)
  local ok, err, errors
  if not t then
    return nil, self:_build_error(error_types.SCHEMA, "Cannot insert a nil element")
  end

  -- Override created_at and id by default value
  t.created_at = timestamp.get_utc()
  t.id = uuid()

  -- Validate schema
  ok, errors = validate(t, self._schema)
  if not ok then
    return nil, self:_build_error(error_types.SCHEMA, errors)
  end

  -- Check UNIQUE values
  ok, err, errors = self:_check_all_unique(t)
  if err then
    return nil, self:_build_error(error_types.DATABASE, err)
  elseif not ok then
    return nil, self:_build_error(error_types.UNIQUE, errors)
  end

  -- Check foreign entities EXIST
  ok, err, errors = self:_check_all_foreign(t)
  if err then
    return nil, self:_build_error(error_types.DATABASE, err)
  elseif not ok then
    return nil, self:_build_error(error_types.FOREIGN, errors)
  end

  local _, stmt_err = self:_execute(self._statements.insert, self:_marshall(t))
  if stmt_err then
    return nil, stmt_err
  else
    return self:_unmarshall(t)
  end
end

-- Execute the prepared UPDATE statement
-- Validate entity's schema + UNIQUE values + FOREIGN KEYS
--
-- @param {table} t Entity to insert (binded to statement)
-- @return {table|nil} Updated entity or nil
-- @return {table|nil} Error if any
function BaseDao:update(t)
  local ok, err, errors
  if not t then
    return nil, self:_build_error(error_types.SCHEMA, "Cannot update a nil element")
  end

  -- Check if exists to prevent upsert and manually set UNSET values (pfffff...)
  local results
  ok, err, results = self:_check_foreign(self._statements.select_one, t)
  if err then
    return nil, self:_build_error(error_types.DATABASE, err)
  elseif not ok then
    return nil
  else
    -- Set UNSET values to prevent cassandra from setting to NULL
    -- @see Test case
    -- @see https://issues.apache.org/jira/browse/DATABASE-7304
    for k, v in pairs(results[1]) do
      if t[k] == nil then
        t[k] = v
      end
    end
  end

  -- Validate schema
  ok, errors = validate(t, self._schema, true)
  if not ok then
    return nil, self:_build_error(error_types.SCHEMA, errors)
  end

  -- Check UNIQUE with update
  ok, err, errors = self:_check_all_unique(t, true)
  if err then
    return nil, self:_build_error(error_types.DATABASE, err)
  elseif not ok then
    return nil, self:_build_error(error_types.UNIQUE, errors)
  end

  -- Check FOREIGN entities
  ok, err, errors = self:_check_all_foreign(t)
  if err then
    return nil, self:_build_error(error_types.DATABASE, err)
  elseif not ok then
    return nil, self:_build_error(error_types.FOREIGN, errors)
  end

  local _, stmt_err = self:_execute(self._statements.update, self:_marshall(t))
  if stmt_err then
    return nil, stmt_err
  else
    return t
  end
end

-- Execute the prepared SELECT_ONE statement as it is
--
-- @param {string} id UUID of element to select
-- @return _execute()
function BaseDao:find_one(id)
  local data, err = self:_execute(self._statements.select_one, { id = id })

  -- Return the 1st and only element of the result set
  if data and utils.table_size(data) > 0 then
    data = table.remove(data, 1)
  else
    data = nil
  end

  return data, err
end

-- Execute a SELECT statement with special WHERE values
-- Build a new prepared statement and cache it for later use
--
-- @see _statements_cache
-- @warning Generated statement will use ALLOW FILTERING
--
-- @param {table} t Optional table from which the WHERE will be built, and the values will be binded
-- @param {number} page_size
-- @param {paging_state} paging_state
--
-- @return _execute()
function BaseDao:find_by_keys(t, page_size, paging_state)
  local where, keys = {}, {}
  local where_str = ""
  local errors

  -- if keys are passed, compute a WHERE statement
  if t and utils.table_size(t) > 0 then
    for k,v in pairs(t) do
      if self._schema[k] and self._schema[k].queryable or k == "id" then
        table.insert(where, string.format("%s = ?", k))
        table.insert(keys, k)
      else
        errors = utils.add_error(errors, k, k.." is not queryable.")
      end
    end

    if errors then
      return nil, self:_build_error(error_types.SCHEMA, errors)
    end

    where_str = "WHERE "..table.concat(where, " AND ").." ALLOW FILTERING"
  end

  local select_query = string.format(self._queries.select.query, where_str)

  -- prepare query in a statement cache
  if not self._statements_cache[select_query] then
    local kong_stmt, err = self:prepare_kong_statement(select_query, keys)
    if err then
      return nil, self:_build_error(error_types.DATABASE, err)
    end
    self._statements_cache[select_query] = kong_stmt
  end

  return self:_execute(self._statements_cache[select_query], t, {
    page_size = page_size,
    paging_state = paging_state
  })
end

-- Execute the prepared SELECT statement as it is
--
-- @param {number} page_size
-- @param {paging_state} paging_state
-- @return find_by_keys()
function BaseDao:find(page_size, paging_state)
  return self:find_by_keys(nil, page_size, paging_state)
end

-- Execute the prepared DELETE statement
--
-- @param {string} id UUID of entity to delete
-- @return {boolean} True if deleted, false if otherwise or not found
-- @return {table|nil} Error if any
function BaseDao:delete(id)
  local exists, err = self:_check_foreign(self._statements.select_one, { id = id })
  if err then
    return false, self:_build_error(error_types.DATABASE, err)
  elseif not exists then
    return false
  end

  return self:_execute(self._statements.delete, { id = id })
end

return BaseDao
