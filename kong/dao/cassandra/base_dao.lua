-- Kong's Cassandra base DAO entity. Provides basic functionnalities on top of
-- lua-resty-cassandra (https://github.com/jbochi/lua-resty-cassandra)
--
-- Entities (APIs, Consumers) having a schema and defined kong_queries can extend
-- this object to benefit from methods such as `insert`, `update`, schema validations
-- (including UNIQUE and FOREIGN check), marshalling of some properties, etc...

local query_builder = require "kong.dao.cassandra.query_builder"
local validations = require "kong.dao.schemas_validation"
local validate = validations.validate
local constants = require "kong.constants"
local cassandra = require "cassandra"
local timestamp = require "kong.tools.timestamp"
local DaoError = require "kong.dao.error"
local stringy = require "stringy"
local Object = require "classic"
local utils = require "kong.tools.utils"
local uuid = require "uuid"

local cassandra_constants = require "cassandra.constants"
local error_types = constants.DATABASE_ERROR_TYPES

local BaseDao = Object:extend()

-- This is important to seed the UUID generator
uuid.seed()

function BaseDao:new(properties)
  self._properties = properties
  self._statements_cache = {}
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

-- Run a statement checking if a row exists (false if it does).
-- @param `kong_query`  kong_query to execute
-- @param `t`           args to bind to the statement
-- @param `is_updating` If true, will ignore UNIQUE if same entity
-- @return `unique`     true if doesn't exist (UNIQUE), false otherwise
-- @return `error`      Error if any during execution
function BaseDao:_check_unique(kong_query, t, is_updating)
  local results, err = self:_execute_kong_query(kong_query, t)
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

-- Run a statement checking if a row exists (true if it does).
-- @param `kong_query` kong_query to execute
-- @param `t`          args to bind to the statement
-- @return `exists`    true if the row exists (FOREIGN), false otherwise
-- @return `error`     Error if any during the query execution
-- @return `results`   Results of the statement if `exists` is true (useful for :update()
function BaseDao:_check_foreign(kong_query, t)
  local results, err = self:_execute_kong_query(kong_query, t)
  if err then
    return false, err
  elseif not results or #results == 0 then
    return false
  else
    return true, nil, results
  end
end

-- Run the FOREIGN exists check on all statements in __foreign.
-- @param  `t`      args to bind to the __foreign statements
-- @return `exists` if all results EXIST, false otherwise
-- @return `error`  Error if any during the query execution
-- @return `errors` A table with the list of not existing foreign entities
function BaseDao:_check_all_foreign(t)
  if not self._queries.__foreign then return true end

  local errors
  for k, kong_query in pairs(self._queries.__foreign) do
    if t[k] and t[k] ~= constants.DATABASE_NULL_ID then
      local exists, err = self:_check_foreign(kong_query, t)
      if err then
        return false, err
      elseif not exists then
        errors = utils.add_error(errors, k, k.." "..t[k].." does not exist")
      end
    end
  end

  return errors == nil, nil, errors
end

-- Run the UNIQUE on all statements in __unique.
-- @param `t`           args to bind to the __unique statements
-- @param `is_updating` If true, will ignore UNIQUE if same entity
-- @return `unique`     true if all results are UNIQUE, false otherwise
-- @return `error`      Error if any during the query  execution
-- @return `errors`     A table with the list of already existing entities
function BaseDao:_check_all_unique(t, is_updating)
  if not self._queries.__unique then return true end

  local errors
  for k, statement in pairs(self._queries.__unique) do
    if t[k] or k == "self" then
      local unique, err = self:_check_unique(statement, t, is_updating)
      if err then
        return false, err
      elseif not unique and k == "self" then
        return false, nil, self._entity.." already exists"
      elseif not unique then
        errors = utils.add_error(errors, k, k.." already exists with value '"..t[k].."'")
      end
    end
  end

  return errors == nil, nil, errors
end

-- Open a Cassandra session on the configured keyspace.
-- @param `keyspace` (Optional) Override the keyspace for this session if specified.
-- @return `session` Opened session
-- @return `error`   Error if any
function BaseDao:_open_session(keyspace)
  local ok, err

  -- Start cassandra session
  local session = cassandra.new()
  session:set_timeout(self._properties.timeout)

  ok, err = session:connect(self._properties.hosts, self._properties.port)
  if not ok then
    return nil, DaoError(err, error_types.DATABASE)
  end

  local times, err = session:get_reused_times()
  if err and err ~= "luasocket does not support reusable sockets" then
    return nil, DaoError(err, error_types.DATABASE)
  end

  if times == 0 or not times then
    ok, err = session:set_keyspace(keyspace and keyspace or self._properties.keyspace)
    if not ok then
      return nil, DaoError(err, error_types.DATABASE)
    end
  end

  return session
end

-- Close the given opened session. Will try to put the session in the socket pool if supported.
-- @param `session` Cassandra session to close
-- @return `error`  Error if any
function BaseDao:_close_session(session)
  -- Back to the pool or close if using luasocket
  local ok, err = session:set_keepalive(self._properties.keepalive)
  if not ok and err == "luasocket does not support reusable sockets" then
    ok, err = session:close()
  end

  if not ok then
    return DaoError(err, error_types.DATABASE)
  end
end

-- Build the array of arguments to pass to lua-resty-cassandra :execute method.
-- Note:
--   Since this method only accepts an ordered list, we build this list from
--   the `args_keys` property of all prepared statement, taking into account special
--   cassandra values (uuid, timestamps, NULL)
-- @param `schema`     A schema with type properties to encode specific values
-- @param `t`          Values to bind to a statement
-- @param `parameters` An ordered list of parameters
-- @return `args`      An ordered list of values to be binded to lua-resty-cassandra :execute
-- @return `error`     Error Cassandra type validation errors
local function encode_cassandra_args(schema, t, args_keys)
  local args_to_bind = {}
  local errors
  for _, column in ipairs(args_keys) do
    local schema_field = schema[column]
    local arg = t[column]

    if schema_field.type == "id" and arg then
      if validations.is_valid_uuid(arg) then
        arg = cassandra.uuid(arg)
      else
        errors = utils.add_error(errors, column, arg.." is an invalid uuid")
      end
    elseif schema_field.type == "timestamp" and arg then
      arg = cassandra.timestamp(arg)
    elseif arg == nil then
      arg = cassandra.null
    end

    table.insert(args_to_bind, arg)
  end

  return args_to_bind, errors
end

-- Get a statement from the cache or prepare it (and thus insert it in the cache).
-- The cache key will be the plain string query representation.
-- @param `kong_query` A kong query from the _queries property.
-- @return `statement` The prepared cassandra statement
-- @return `cache_key` The cache key used to store it into the cache
-- @return `error`     Error if any during the query preparation
function BaseDao:_get_or_prepare(kong_query)
  local query
  if type(kong_query) == "string" then
    query = kong_query
  elseif kong_query.query then
    query = kong_query.query
  else
    -- Cannot be prepared (probably a BatchStatement)
    return kong_query
  end

  local statement, err
  -- Retrieve the prepared statement from cache or prepare and cache
  if self._statements_cache[kong_query.query] then
    statement = self._statements_cache[kong_query.query].statement
  else
    statement, err = self:prepare_kong_statement(kong_query)
    if err then
      return nil, query, err
    end
  end

  return statement, query
end

-- Execute a statement, BatchStatement or even plain string query.
-- Opens a socket, execute the statement, puts the socket back into the
-- socket pool and returns a parsed result.
-- @param `statement` Prepared statement, plain string query or BatchStatement.
-- @param `args`      (Optional) Arguments to the query, simply passed to lua-resty-cassandra's :execute()
-- @param `options`   (Optional) Options to give to lua-resty-cassandra's :execute()
-- @param `keyspace`  (Optional) Override the keyspace for this query if specified.
-- @return `results`  If results set are ROWS, a table with an array of unmarshalled rows and a `next_page` property if the results have a paging_state.
-- @return `error`    An error if any during the whole execution (sockets/query execution)
function BaseDao:_execute(statement, args, options, keyspace)
  local session, err = self:_open_session(keyspace)
  if err then
    return nil, err
  end

  if options and options.auto_paging then
    local _, rows, page, err = session:execute(statement, args, options)
    for i, row in ipairs(rows) do
      rows[i] = self:_unmarshall(row)
    end
    return _, rows, page, err
  end

  local results, err = session:execute(statement, args, options)
  if err then
    err = DaoError(err, error_types.DATABASE)
  end

  local socket_err = self:_close_session(session)
  if socket_err then
    return nil, socket_err
  end

  -- Parse result
  if results and results.type == "ROWS" then
    -- do we have more pages to fetch? if so, alias the paging_state
    if results.meta.has_more_pages then
      results.next_page = results.meta.paging_state
    end

    -- only the DAO needs those, it should be transparant in the application
    results.meta = nil
    results.type = nil

    for i, row in ipairs(results) do
      results[i] = self:_unmarshall(row)
    end

    return results, err
  elseif results and results.type == "VOID" then
    -- result is not a set of rows, let's return a boolean to indicate success
    return err == nil, err
  else
    return results, err
  end
end

-- Execute a kong_query (_queries property of DAO entities).
-- Will prepare the query before execution and cache the prepared statement.
-- Will create an arguments array for lua-resty-cassandra's :execute()
-- @param `kong_query`   The kong_query to execute
-- @param `args_to_bind` Key/value table of arguments to bind
-- @param `options`      Options to pass to lua-resty-cassandra :execute()
-- @return :_execute()
function BaseDao:_execute_kong_query(operation, args_to_bind, options)
  -- Prepare query and cache the prepared statement for later call
  local statement, cache_key, err = self:_get_or_prepare(operation)
  if err then
    return nil, err
  end

  -- Build args array if operation has some
  local args
  if operation.args_keys and args_to_bind then
    local errors
    args, errors = encode_cassandra_args(self._schema, args_to_bind, operation.args_keys)
    if errors then
      return nil, DaoError(errors, error_types.INVALID_TYPE)
    end
  end

  -- Execute statement
  local results, err
  results, err = self:_execute(statement, args, options)
  if err and err.cassandra_err_code == cassandra_constants.error_codes.UNPREPARED then
    if ngx then
      ngx.log(ngx.NOTICE, "Cassandra did not recognize prepared statement \""..cache_key.."\". Re-preparing it and re-trying the query. (Error: "..err..")")
    end
    -- If the statement was declared unprepared, clear it from the cache, and try again.
    self._statements_cache[cache_key] = nil
    return self:_execute_kong_query(operation, args_to_bind, options)
  end

  return results, err
end

----------------------
-- PUBLIC INTERFACE --
----------------------

-- Prepare a statement used by kong and insert it into the statement cache.
-- Note:
--   Since lua-resty-cassandra doesn't support binding by name yet, we need
--   to keep a record of properties to bind for each statement. Thus, a "kong query"
--   is an object made of a prepared statement and an array of columns to bind.
--   See :_execute_kong_query() for the usage of this args_keys array doing the binding.
-- @param `kong_query` The kong_query to prepare and insert into the cache.
-- @return `statement` The prepared statement, ready to be used by lua-resty-cassandra.
-- @return `error`     Error if any during the preparation of the statement
function BaseDao:prepare_kong_statement(kong_query)
  -- _queries can contain strings or tables with string + keys of arguments to bind
  local query
  if type(kong_query) == "string" then
    query = kong_query
  elseif kong_query.query then
    query = kong_query.query
  end

  -- handle SELECT queries with %s for dynamic select by keys
  local query_to_prepare = string.format(query, "")
  query_to_prepare = stringy.strip(query_to_prepare)

  local session, err = self:_open_session()
  if err then
    return nil, err
  end

  local prepared_stmt, prepare_err = session:prepare(query_to_prepare)

  local err = self:_close_session(session)
  if err then
    return nil, err
  end

  if prepare_err then
    return nil, DaoError("Failed to prepare statement: \""..query_to_prepare.."\". "..prepare_err, error_types.DATABASE)
  else
    -- cache key is the non-striped/non-formatted query from _queries
    self._statements_cache[query] = {
      query = query,
      args_keys = kong_query.args_keys,
      statement = prepared_stmt
    }

    return prepared_stmt
  end
end


-- Execute the INSERT kong_query of a DAO entity.
-- Validates the entity's schema + UNIQUE values + FOREIGN KEYS.
-- @param `t`       A table representing the entity to insert
-- @return `result` Inserted entity or nil
-- @return `error`  Error if any during the execution
function BaseDao:insert(t)
  local ok, err, errors
  if not t then
    return nil, DaoError("Cannot insert a nil element", error_types.SCHEMA)
  end

  -- Populate the entity with any default/overriden values and validate it
  ok, errors = validate(t, self._schema, { dao_insert = function(field)
    if field.type == "id" then
      return uuid()
    elseif field.type == "timestamp" then
      return timestamp.get_utc()
    end
  end })
  if not ok then
    return nil, DaoError(errors, error_types.SCHEMA)
  end

  -- Check UNIQUE values
  ok, err, errors = self:_check_all_unique(t)
  if err then
    return nil, DaoError(err, error_types.DATABASE)
  elseif not ok then
    return nil, DaoError(errors, error_types.UNIQUE)
  end

  -- Check foreign entities EXIST
  ok, err, errors = self:_check_all_foreign(t)
  if err then
    return nil, DaoError(err, error_types.DATABASE)
  elseif not ok then
    return nil, DaoError(errors, error_types.FOREIGN)
  end

  local insert_q, columns = query_builder.insert(self._table, t)

  local _, stmt_err = self:_execute_kong_query({ query = insert_q, args_keys = columns }, self:_marshall(t))
  if stmt_err then
    return nil, stmt_err
  else
    return self:_unmarshall(t)
  end
end

-- Execute the UPDATE kong_query of a DAO entity.
-- Validate entity's schema + UNIQUE values + FOREIGN KEYS.
-- @param `t`       A table representing the entity to insert
-- @return `result` Updated entity or nil
-- @return `error`  Error if any during the execution
function BaseDao:update(t)
  local ok, err, errors
  if not t then
    return nil, DaoError("Cannot update a nil element", error_types.SCHEMA)
  end

  -- Extract primary keys from the entity
  local t_without_primary_keys = utils.deep_copy(t)
  local t_only_primary_keys = {}
  for _, v in ipairs(self._primary_key) do
    t_only_primary_keys[v] = t[v]
    t_without_primary_keys[v] = nil
  end

  local unique_q, unique_q_columns = query_builder.select(self._table, t_only_primary_keys)

  -- Check if exists to prevent upsert and manually set UNSET values (pfffff...)
  local results
  ok, err, results = self:_check_foreign({query = unique_q, args_keys = unique_q_columns}, t_only_primary_keys)
  if err then
    return nil, err
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
  ok, errors = validate(t, self._schema, {is_update = true})
  if not ok then
    return nil, DaoError(errors, error_types.SCHEMA)
  end

  -- Check UNIQUE with update
  ok, err, errors = self:_check_all_unique(t, true)
  if err then
    return nil, DaoError(err, error_types.DATABASE)
  elseif not ok then
    return nil, DaoError(errors, error_types.UNIQUE)
  end

  -- Check FOREIGN entities
  ok, err, errors = self:_check_all_foreign(t)
  if err then
    return nil, DaoError(err, error_types.DATABASE)
  elseif not ok then
    return nil, DaoError(errors, error_types.FOREIGN)
  end

  local update_q, columns = query_builder.update(self._table, t_without_primary_keys, t_only_primary_keys, self._primary_key)

  local _, stmt_err = self:_execute_kong_query({query = update_q, args_keys = columns}, self:_marshall(t))
  if stmt_err then
    return nil, stmt_err
  else
    return self:_unmarshall(t)
  end
end

-- Execute the SELECT_ONE kong_query of a DAO entity.
-- @param  `args_keys` Keys to bind to the `select_one` query.
-- @return `result`    The first row of the _execute_kong_query() return value
function BaseDao:find_one(where_t)
  local select_q, where_columns = query_builder.select(self._table, where_t)

  local data, err = self:_execute_kong_query({ query = select_q, args_keys = where_columns }, where_t)

  -- Return the 1st and only element of the result set
  if data and utils.table_size(data) > 0 then
    data = table.remove(data, 1)
  else
    data = nil
  end

  return data, err
end

-- Execute the SELECT kong_query of a DAO entity with a special WHERE clause.
-- @warning Generated statement will use `ALLOW FILTERING` in their queries.
-- @param `t`            (Optional) Keys by which to find an entity.
-- @param `page_size`    Size of the page to retrieve (number of rows).
-- @param `paging_state` Start page from given offset. See lua-resty-cassandra's :execute() option.
-- @return _execute_kong_query()
function BaseDao:find_by_keys(where_t, page_size, paging_state)
  --[[local select_where_query, args_keys, errors = self:_build_where_query(self._queries.select.query, where_t)
  if errors then
    return nil, errors
  end]]

  local select_q, where_columns = query_builder.select(self._table, where_t, self._primary_key)

  return self:_execute_kong_query({ query = select_q, args_keys = where_columns }, where_t, {
    page_size = page_size,
    paging_state = paging_state
  })
end

-- Execute the SELECT kong_query of a DAO entity.
-- @param `page_size`    Size of the page to retrieve (number of rows).
-- @param `paging_state` Start page from given offset. See lua-resty-cassandra's :execute() option.
-- @return find_by_keys()
function BaseDao:find(page_size, paging_state)
  return self:find_by_keys(nil, page_size, paging_state)
end

-- Execute the SELECT kong_query of a DAO entity.
-- @param `id`       uuid of the entity to delete
-- @return `success` True if deleted, false if otherwise or not found
-- @return `error`   Error if any during the query execution
function BaseDao:delete(where_t)
  local select_q, where_columns = query_builder.select(self._table, where_t, self._primary_key)

  local exists, err = self:_check_foreign({ query = select_q, args_keys = where_columns }, where_t)
  if err then
    return false, err
  elseif not exists then
    return false
  end

  local delete_q, where_columns = query_builder.delete(self._table, where_t, self._primary_key)

  return self:_execute_kong_query({ query = delete_q, args_keys = where_columns }, where_t)
end

function BaseDao:drop()
  if self._queries.drop then
    return self:_execute_kong_query(self._queries.drop)
  end
end

return BaseDao
