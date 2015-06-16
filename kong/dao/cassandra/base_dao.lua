-- Kong's Cassandra base DAO entity. Provides basic functionnalities on top of
-- lua-resty-cassandra (https://github.com/jbochi/lua-resty-cassandra)
--
-- Entities (APIs, Consumers) having a schema and defined kong_queries can extend
-- this object to benefit from methods such as `insert`, `update`, schema validations
-- (including UNIQUE and FOREIGN check), marshalling of some properties, etc...

local query_builder = require "kong.dao.cassandra.query_builder"
local validations = require "kong.dao.schemas_validation"
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
    local schema_field = schema.fields[column]
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
  local results, err = self:_execute(statement, args, options)
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

function BaseDao:check_unique_fields(t, is_update)
  local errors

  for k, field in pairs(self._schema.fields) do
    if field.unique and t[k] ~= nil then
      local res, err = self:find_by_keys {[k] = t[k]}
      if err then
        return false, nil, "Error during UNIQUE check: "..err.message
      elseif res and #res > 0 then
        local is_self = true
        if is_update then
          -- If update, check if the retrieved entity is not the entity itself
          res = res[1]
          for key_k, key_v in ipairs(self._primary_key) do
            if t[key_k] ~= res[key_k] then
              is_self = false
              break
            end
          end
        else
          is_self = false
        end

        if not is_self then
          errors = utils.add_error(errors, k, k.." already exists with value '"..t[k].."'")
        end
      end
    end
  end

  return errors == nil, errors
end

function BaseDao:check_foreign_fields(t)
  local errors, foreign_type, foreign_field, res, err

  for k, field in pairs(self._schema.fields) do
    if field.foreign ~= nil and type(field.foreign) == "string" then
      foreign_type, foreign_field = unpack(stringy.split(field.foreign, ":"))
      if foreign_type and foreign_field and self._factory[foreign_type] and t[k] ~= nil and t[k] ~= constants.DATABASE_NULL_ID then
        res, err = self._factory[foreign_type]:find_by_keys {[foreign_field] = t[k]}
        if err then
          return false, nil, "Error during FOREIGN check: "..err.message
        elseif not res or #res == 0 then
          errors = utils.add_error(errors, k, k.." "..t[k].." does not exist")
        end
      end
    end
  end

  return errors == nil, errors
end

-- Execute the INSERT kong_query of a DAO entity.
-- Validates the entity's schema + UNIQUE values + FOREIGN KEYS.
-- @param `t`       A table representing the entity to insert
-- @return `result` Inserted entity or nil
-- @return `error`  Error if any during the execution
function BaseDao:insert(t)
  assert(t ~= nil, "Cannot insert a nil element")
  assert(type(t) == "table", "Entity to insert must be a table")

  local ok, db_err, errors

  -- Populate the entity with any default/overriden values and validate it
  errors = validations.validate(t, self, {
    dao_insert = function(field)
      if field.type == "id" then
        return uuid()
      elseif field.type == "timestamp" then
        return timestamp.get_utc()
      end
    end
  })
  if errors then
    return nil, errors
  end

  ok, errors = validations.on_insert(t, self._schema, self._factory)
  if not ok then
    return nil, errors
  end

  ok, errors, db_err = self:check_unique_fields(t)
  if db_err then
    return nil, DaoError(db_err, error_types.DATABASE)
  elseif not ok then
    return nil, DaoError(errors, error_types.UNIQUE)
  end

  ok, errors, db_err = self:check_foreign_fields(t)
  if db_err then
    return nil, DaoError(db_err, error_types.DATABASE)
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
  assert(t ~= nil, "Cannot update a nil element")
  assert(type(t) == "table", "Entity to update must be a table")

  local ok, db_err, errors

  -- Extract primary keys from the entity
  local t_without_primary_keys = utils.deep_copy(t)
  local t_only_primary_keys = {}
  for _, v in ipairs(self._primary_key) do
    t_only_primary_keys[v] = t[v]
    t_without_primary_keys[v] = nil
  end

  -- Check if exists to prevent upsert
  local res, err = self:find_by_keys(t_only_primary_keys)
  if err then
    return false, err
  elseif not res or #res == 0 then
    return false
  end

  -- Validate schema
  errors = validations.validate(t, self, { is_update = next(t_without_primary_keys) ~= nil, primary_key = t_only_primary_keys}) -- hack
  if errors then
    return nil, errors
  end

  ok, errors, db_err = self:check_unique_fields(t, true)
  if db_err then
    return nil, DaoError(db_err, error_types.DATABASE)
  elseif not ok then
    return nil, DaoError(errors, error_types.UNIQUE)
  end

  ok, errors, db_err = self:check_foreign_fields(t)
  if db_err then
    return nil, DaoError(db_err, error_types.DATABASE)
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
function BaseDao:find_by_primary_key(where_t)
  assert(self._primary_key ~= nil and type(self._primary_key) == "table" , "Entity does not have primary_keys")

  local primary_keys = {}
  for i, k in pairs(self._primary_key) do
    if i == 1 and not where_t[k] then
      -- The primary key was not specified, Cassandra won't be able to retrieve anything
      return nil
    else
      primary_keys[k] = where_t[k]
    end
  end

  local select_q, where_columns = query_builder.select(self._table, primary_keys)
  local data, err = self:_execute_kong_query({ query = select_q, args_keys = where_columns }, primary_keys)

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
  assert(where_t ~= nil, "where_t must not be nil")

  -- Test if exists first
  local res, err = self:find_by_keys(where_t)
  if err then
    return false, err
  elseif not res or #res == 0 then
    return false
  end

  local delete_q, where_columns = query_builder.delete(self._table, where_t, self._primary_key)
  return self:_execute_kong_query({ query = delete_q, args_keys = where_columns }, where_t)
end

function BaseDao:drop()
  local truncate_q = query_builder.truncate(self._table)
  return self:_execute_kong_query(truncate_q)
end

return BaseDao
