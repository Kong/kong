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
  if self._schema then
    self._primary_key = self._schema.primary_key
    self._clustering_key = self._schema.clustering_key
    local indexes = {}
    for field_k, field_v in pairs(self._schema.fields) do
      if field_v.queryable then
        indexes[field_k] = true
      end
    end

    self._column_family_details = {
      primary_key = self._primary_key,
      clustering_key = self._clustering_key,
      indexes = indexes
    }
  end

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
function BaseDao:get_or_prepare_stmt(query)
  if type(query) == "string" then
    query = stringy.strip(query)
  else
    -- Cannot be prepared (probably a BatchStatement)
    return query
  end

  local statement, err
  -- Retrieve the prepared statement from cache or prepare and cache
  if self._statements_cache[query] then
    statement = self._statements_cache[query]
  else
    statement, err = self:prepare(query)
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
function BaseDao:execute(query, columns, args_to_bind, options)
  -- Prepare query and cache the prepared statement for later call
  local statement, cache_key, err = self:get_or_prepare_stmt(query)
  if err then
    return nil, err
  end

  -- Build args array if operation has some
  local args
  if columns and args_to_bind then
    local errors
    args, errors = encode_cassandra_args(self._schema, args_to_bind, columns)
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
    return self:execute(query, columns, args_to_bind, options)
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
--   See :execute() for the usage of this args_keys array doing the binding.
-- @param `kong_query` The kong_query to prepare and insert into the cache.
-- @return `statement` The prepared statement, ready to be used by lua-resty-cassandra.
-- @return `error`     Error if any during the preparation of the statement
function BaseDao:prepare(query)
  assert(type(query) == "string", "Query to prepare must be a string")
  query = stringy.strip(query)

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
    return nil, DaoError("Failed to prepare statement: \""..query.."\". "..prepare_err, error_types.DATABASE)
  else
    -- cache key is the non-striped/non-formatted query from _queries
    self._statements_cache[query] = prepared_stmt
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
          for _, key in ipairs(self._primary_key) do
            if t[key] ~= res[key] then
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
  local _, stmt_err = self:execute(insert_q, columns, self:_marshall(t))
  if stmt_err then
    return nil, stmt_err
  else
    return self:_unmarshall(t)
  end
end

local function extract_primary_key(t, primary_key, clustering_key)
  local t_no_primary_key = utils.deep_copy(t)
  local t_primary_key  = {}
  for _, key in ipairs(primary_key) do
    t_primary_key[key] = t[key]
    t_no_primary_key[key] = nil
  end
  if clustering_key then
    for _, key in ipairs(clustering_key) do
      t_primary_key[key] = t[key]
      t_no_primary_key[key] = nil
    end
  end
  return t_primary_key, t_no_primary_key
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

  -- Check if exists to prevent upsert
  local res, err = self:find_by_primary_key(t)
  if err then
    return false, err
  elseif not res then
    return false
  end

  -- Validate schema
  errors = validations.validate(t, self, {is_update = true})
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

  -- Extract primary key from the entity
  local t_primary_key, t_no_primary_key = extract_primary_key(t, self._primary_key, self._clustering_key)
  local update_q, columns = query_builder.update(self._table, t_no_primary_key, t_primary_key)

  local _, stmt_err = self:execute(update_q, columns, self:_marshall(t))
  if stmt_err then
    return nil, stmt_err
  else
    return self:_unmarshall(t)
  end
end

-- Execute the SELECT_ONE kong_query of a DAO entity.
-- @param  `args_keys` Keys to bind to the `select_one` query.
-- @return `result`    The first row of the execute() return value
function BaseDao:find_by_primary_key(where_t)
  assert(self._primary_key ~= nil and type(self._primary_key) == "table" , "Entity does not have a primary_key")
  assert(where_t ~= nil and type(where_t) == "table", "where_t must be a table")

  local t_primary_key = extract_primary_key(where_t, self._primary_key)

  if next(t_primary_key) == nil then
    return nil
  end

  local select_q, where_columns = query_builder.select(self._table, t_primary_key, self._column_family_details, nil, true)
  local data, err = self:execute(select_q, where_columns, t_primary_key)

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
-- @return execute()
function BaseDao:find_by_keys(where_t, page_size, paging_state)
  local select_q, where_columns, needs_filtering = query_builder.select(self._table, where_t, self._column_family_details)
  local res, err = self:execute(select_q, where_columns, where_t, {
    page_size = page_size,
    paging_state = paging_state
  })

  return res, err, needs_filtering
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
  assert(self._primary_key ~= nil and type(self._primary_key) == "table" , "Entity does not have a primary_key")
  assert(where_t ~= nil and type(where_t) == "table", "where_t must be a table")

  -- Test if exists first
  local res, err = self:find_by_keys(where_t)
  if err then
    return false, err
  elseif not res or #res == 0 then
    return false
  end

  local t_primary_key = extract_primary_key(where_t, self._primary_key, self._clustering_key)
  local delete_q, where_columns = query_builder.delete(self._table, t_primary_key)
  return self:execute(delete_q, where_columns, where_t)
end

function BaseDao:drop()
  local truncate_q = query_builder.truncate(self._table)
  return self:execute(truncate_q)
end

return BaseDao
