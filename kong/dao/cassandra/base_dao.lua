---
-- Kong's Cassandra base DAO module. Provides functionalities on top of
-- lua-cassandra (https://github.com/thibaultCha/lua-cassandra) for schema validations,
-- CRUD operations, preparation and caching of executed statements, etc...
--
-- @see http://thibaultcha.github.io/lua-cassandra/manual/README.md.html

local query_builder = require "kong.dao.cassandra.query_builder"
local validations = require "kong.dao.schemas_validation"
local constants = require "kong.constants"
local cassandra = require "cassandra"
local timestamp = require "kong.tools.timestamp"
local DaoError = require "kong.dao.error"
local stringy = require "stringy"
local Object = require "classic"
local utils = require "kong.tools.utils"
local uuid = require "lua_uuid"

local cassandra_constants = cassandra.constants
local error_types = constants.DATABASE_ERROR_TYPES

local BaseDao = Object:extend()

local function session_uniq_addr(session)
  return session.host..":"..session.port
end

---
-- @local
-- Build the array of arguments to pass to lua-cassandra's :execute method.
-- Note:
--   Since this method only accepts an ordered list, we build this list from
--   the entity `t` and an (ordered) array of parameters for a query, taking
--   into account special cassandra values (uuid, timestamps, NULL).
-- @param[type=table] schema A schema with type properties to encode specific values
-- @param[type=table] t      Values to bind to a statement
-- @param[type=table] parameters An ordered list of parameters
-- @treturn table An ordered list of values to be binded to lua-resty-cassandra :execute
-- @treturn table Error Cassandra type validation errors
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

--- Public interface.
-- Public methods developers can use in Kong core or in any plugin.
-- @section public

---
-- Bind a table of arguments to a query depending on the entity's schema,
-- and then execute the query via **:_execute()**.
-- @param[type=string] query The query to execute
-- @param[type=table] args_to_bind Key/value table of arguments to bind
-- @param[type=stable] options Options to pass to lua-cassandra's :execute()
-- @return return values of _execute()
-- @see _execute
function BaseDao:execute(query, columns, args_to_bind, options)
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
  return self:_execute(query, args, options)
end

--- Children DAOs interface.
-- Those methds are to be used in any child DAO and will perform the named operations
-- the entity they represent.
-- @section inherited

---
-- Insert a row in the defined column family (defined by the **_table** attribute).
-- Perform schema validation, 'UNIQUE' checks, 'FOREIGN' checks.
-- @see check_unique_fields
-- @see check_foreign_fields
-- @param[table=table] t A table representing the entity to insert
-- @treturn table Inserted entity or nil
-- @treturn table Error if any during the execution
function BaseDao:insert(t)
  assert(t ~= nil, "Cannot insert a nil element")
  assert(type(t) == "table", "Entity to insert must be a table")

  local ok, db_err, errors, self_err

  -- Populate the entity with any default/overriden values and validate it
  ok, errors, self_err = validations.validate_entity(t, self._schema, {
    dao = self._factory,
    dao_insert = function(field)
      if field.type == "id" then
        return uuid()
      elseif field.type == "timestamp" then
        return timestamp.get_utc()
      end
    end
  })
  if self_err then
    return nil, self_err
  elseif not ok then
    return nil, DaoError(errors, error_types.SCHEMA)
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

---
-- When updating a row that has a json-as-text column (ex: plugin.config),
-- we want to avoid overriding it with a partial value.
-- Ex: config.key_name + config.hide_credential, if we update only one field,
-- the other should be preserved. Of course this only applies in partial update.
local function fix_tables(t, old_t, schema)
  for k, v in pairs(schema.fields) do
    if t[k] ~= nil and v.schema then
      local s = type(v.schema) == "function" and v.schema(t) or v.schema
      for s_k, s_v in pairs(s.fields) do
        if not t[k][s_k] and old_t[k] then
          t[k][s_k] = old_t[k][s_k]
        end
      end
      fix_tables(t[k], old_t[k], s)
    end
  end
end

---
-- Update an entity: find the row with the given PRIMARY KEY and update the other values
-- Performs schema validation, 'UNIQUE' and 'FOREIGN' checks.
-- @see check_unique_fields
-- @see check_foreign_fields
-- @param[type=table] t A table representing the entity to update. It **must** contain the entity's PRIMARY KEY (can be composite).
-- @param[type=boolean] full  If **true**, set to NULL any column not in the `t` parameter, such as a PUT query would do for example.
-- @treturn table Updated entity or nil
-- @treturn table Error if any during the execution
function BaseDao:update(t, full)
  assert(t ~= nil, "Cannot update a nil element")
  assert(type(t) == "table", "Entity to update must be a table")

  local ok, db_err, errors, self_err

  -- Check if exists to prevent upsert
  local res, err = self:find_by_primary_key(t)
  if err then
    return false, err
  elseif not res then
    return false
  end

  if not full then
    fix_tables(t, res, self._schema)
  end

  -- Validate schema
  ok, errors, self_err = validations.validate_entity(t, self._schema, {
    partial_update = not full,
    full_update = full,
    dao = self._factory
  })
  if self_err then
    return nil, self_err
  elseif not ok then
    return nil, DaoError(errors, error_types.SCHEMA)
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

  -- If full, add `null` values to the SET part of the query for nil columns
  if full then
    for k, v in pairs(self._schema.fields) do
      if not t[k] and not v.immutable then
        t_no_primary_key[k] = cassandra.null
      end
    end
  end

  local update_q, columns = query_builder.update(self._table, t_no_primary_key, t_primary_key)

  local _, stmt_err = self:execute(update_q, columns, self:_marshall(t))
  if stmt_err then
    return nil, stmt_err
  else
    return self:_unmarshall(t)
  end
end

---
-- Retrieve a row at given PRIMARY KEY.
-- @param[type=table] where_t A table containing the PRIMARY KEY (it can be composite, hence be multiple columns as keys and their values) of the row to retrieve.
-- @treturn table The first row of the result.
-- @treturn table Error if any during the execution
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

---
-- Retrieve a set of rows from the given columns/value table with a given
-- 'WHERE' clause.
-- @param[type=table] where_t (Optional) columns/values table by which to find an entity.
-- @param[type=number] page_size Size of the page to retrieve (number of rows).
-- @param[type=string] paging_state Start page from given offset. See lua-cassandra's related **:execute()** option.
-- @treturn table An array (of possible length 0) of entities as the result of the query
-- @treturn table An error if any
-- @treturn boolean A boolean indicating if the 'ALLOW FILTERING' clause was needed by the query
function BaseDao:find_by_keys(where_t, page_size, paging_state)
  local select_q, where_columns, filtering = query_builder.select(self._table, where_t, self._column_family_details)
  local res, err = self:execute(select_q, where_columns, where_t, {
    page_size = page_size,
    paging_state = paging_state
  })

  return res, err, filtering
end

---
-- Retrieve the number of rows in the related column family matching a possible 'WHERE' clause.
-- @param[type=table] where_t (Optional) columns/values table by which to count entities.
-- @param[type=string] paging_state Start page from given offset. See lua-cassandra's related **:execute()** option.
-- @treturn number The number of rows matching the specified criteria
-- @treturn table An error if any
-- @treturn boolean A boolean indicating if the 'ALLOW FILTERING' clause was needed by the query
function BaseDao:count_by_keys(where_t, paging_state)
  local count_q, where_columns, filtering = query_builder.count(self._table, where_t, self._column_family_details)
  local res, err = self:execute(count_q, where_columns, where_t, {
    paging_state = paging_state
  })

  return (#res >= 1 and table.remove(res, 1).count or 0), err, filtering
end

---
-- Retrieve a page of rows from the related column family.
-- @param[type=number] page_size Size of the page to retrieve (number of rows). The default is the default value from lua-cassandra.
-- @param[type=string] paging_state Start page from given offset. See lua-cassandra's related **:execute()** option.
-- @return return values of find_by_keys()
-- @see find_by_keys
function BaseDao:find(page_size, paging_state)
  return self:find_by_keys(nil, page_size, paging_state)
end

---
-- Delete the row with PRIMARY KEY from the configured table (**_table** attribute).
-- @param[table=table] where_t A table containing the PRIMARY KEY (columns/values) of the row to delete
-- @treturn boolean True if deleted, false if otherwise or not found
-- @treturn table   Error if any during the query execution or the cascade delete hook
function BaseDao:delete(where_t)
  assert(self._primary_key ~= nil and type(self._primary_key) == "table" , "Entity does not have a primary_key")
  assert(where_t ~= nil and type(where_t) == "table", "where_t must be a table")

  -- Test if exists first
  local res, err = self:find_by_primary_key(where_t)
  if err then
    return false, err
  elseif not res then
    return false
  end

  local t_primary_key = extract_primary_key(where_t, self._primary_key, self._clustering_key)
  local delete_q, where_columns = query_builder.delete(self._table, t_primary_key)
  local results, err = self:execute(delete_q, where_columns, where_t)
  if err then
    return false, err
  end

  -- Delete successful, trigger cascade delete hooks if any.
  local foreign_err
  for _, hook in ipairs(self._cascade_delete_hooks) do
    foreign_err = select(2, hook(t_primary_key))
    if foreign_err then
      return false, foreign_err
    end
  end

  return results
end

---
-- Truncate the table related to this DAO (the **_table** attribute).
-- Only executes a 'TRUNCATE' query using the @{execute} method.
-- @return Return values of execute()
-- @see execute
function BaseDao:drop()
  local truncate_q = query_builder.truncate(self._table)
  return self:execute(truncate_q)
end

--- Optional overrides.
-- Can be optionally overriden by a child DAO.
-- @section optional

--- Constructor.
-- Instanciate a new Cassandra DAO. This method is to be overriden from the
-- child class and called once the child class has a schema set.
-- @param properties Cassandra properties from the configuration file.
-- @treturn table Instanciated DAO.
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
  self._cascade_delete_hooks = {}
end

---
-- Marshall an entity.
-- Executed on each entity insertion to serialize
-- eventual properties for Cassandra storage.
-- Does nothing by default, must be overriden for entities where marshalling applies.
-- @see _unmarshall
-- @param[type=table] t Entity to marshall.
-- @treturn table Serialized entity.
function BaseDao:_marshall(t)
  return t
end

---
-- Unmarshall an entity.
-- Executed each time an entity is being retrieved from Cassandra
-- to deserialize properties serialized by `:_mashall()`,
-- Does nothing by default, must be overriden for entities where marshalling applies.
-- @see _marshall
-- @param[type=table] t Entity to unmarshall.
-- @treturn table Deserialized entity.
function BaseDao:_unmarshall(t)
  return t
end

--- Private methods.
-- For internal use in the base_dao itself or advanced usage in a child DAO.
-- @section private

---
-- Open a session on the configured keyspace.
-- @param[type=string]  keyspace (Optional) Override the keyspace for this session if specified.
-- @treturn table Opened session
-- @treturn table Error if any
function BaseDao:_open_session(keyspace)
  local ok, err

  -- Start cassandra session
  local session = cassandra:new()
  session:set_timeout(self._properties.timeout)

  local options = self._factory:get_session_options()

  ok, err = session:connect(self._properties.hosts or self._properties.contact_points, nil, options)
  if not ok then
    return nil, DaoError(err, error_types.DATABASE)
  end

  local times, err = session:get_reused_times()
  if err and err.message ~= "luasocket does not support reusable sockets" then
    return nil, DaoError(err, error_types.DATABASE)
  end

  if times == 0 or not times then
    ok, err = session:set_keyspace(keyspace ~= nil and keyspace or self._properties.keyspace)
    if not ok then
      return nil, DaoError(err, error_types.DATABASE)
    end
  end

  return session
end

---
-- Close the given opened session.
-- Will try to put the session in the socket pool for re-use if supported
-- by the current phase.
-- @param[type=table] session Cassandra session to close
-- @treturn table Error if any
function BaseDao:_close_session(session)
  -- Back to the pool or close if using luasocket
  local ok, err = session:set_keepalive(self._properties.keepalive)
  if not ok and err.message == "luasocket does not support reusable sockets" then
    ok, err = session:close()
  end

  if not ok then
    return DaoError(err, error_types.DATABASE)
  end
end

---
-- @local
-- Prepare a query and insert it into the statements cache.
-- @param[type=string] query The query to prepare
-- @treturn table The prepared statement, ready to be used by lua-cassandra.
-- @treturn table Error if any during the preparation of the statement
-- @see get_or_prepare_stmt
local function prepare_stmt(self, session, query)
  assert(type(query) == "string", "Query to prepare must be a string")
  query = stringy.strip(query)

  local prepared_stmt, prepare_err = session:prepare(query)
  if prepare_err then
    return nil, DaoError("Failed to prepare statement: \""..query.."\". "..prepare_err, error_types.DATABASE)
  else
    local session_addr = session_uniq_addr(session)
    -- cache of prepared statements must be specific to each node
    if not self._statements_cache[session_addr] then
      self._statements_cache[session_addr] = {}
    end

    -- cache key is the non-striped/non-formatted query from _queries
    self._statements_cache[session_addr][query] = prepared_stmt
    return prepared_stmt
  end
end

---
-- Get a prepared statement from the statements cache or prepare it (and thus insert it in the cache).
-- The cache is unique for each Cassandra contact_point (base on the host and port).
-- The statement's cache key will be the plain string query representation.
-- @param[type=string] query The query to prepare
-- @treturn table The prepared statement, ready to be used by lua-cassandra.
-- @treturn string The cache key used to store it into the cache
-- @treturn table Error if any during the query preparation
function BaseDao:get_or_prepare_stmt(session, query)
  if type(query) ~= "string" then
    -- Cannot be prepared (probably a BatchStatement)
    return query
  end

  local statement, err
  local session_addr = session_uniq_addr(session)
  -- Retrieve the prepared statement from cache or prepare and cache
  if self._statements_cache[session_addr] and self._statements_cache[session_addr][query] then
    statement = self._statements_cache[session_addr][query]
  else
    statement, err = prepare_stmt(self, session, query)
    if err then
      return nil, query, err
    end
  end

  return statement, query
end

--- Execute a query (internally).
-- This method should be called with the proper **args** formatting (as an array). See
-- **:execute()** for building this parameter.
-- Make sure the query is either prepared and cached, or retrieved from the
-- current cache.
-- Opens a socket, execute the statement, puts the socket back into the
-- socket pool and returns a parsed result.
--
-- @see execute
-- @see get_or_prepare_stmt
-- @see _close_session
--
-- @param query Plain string query or BatchStatement.
-- @param[type=table] args (Optional) Arguments to the query, as an array. Simply passed to lua-cassandra's :execute()
-- @param[type=table] options (Optional) Options to give to lua-resty-cassandra's :execute()
-- @param[type=string] keyspace (Optional) Override the keyspace for this query if specified.
-- @treturn table If the result set consists of ROWS, a table with an array of unmarshalled rows and a `next_page` property if the results have a paging_state.
-- @treturn table An error if any during the whole execution (sockets/query execution)
function BaseDao:_execute(query, args, options, keyspace)
  local session, err = self:_open_session(keyspace)
  if err then
    return nil, err
  end

  -- Prepare query and cache the prepared statement for later call
  local statement, cache_key, err = self:get_or_prepare_stmt(session, query)
  if err then
    if options and options.auto_paging then
      -- Allow the iteration to run once and thus catch the error
      return function() return {}, err end
    end
    return nil, err
  end

  if options and options.auto_paging then
    local _, rows, err, page = session:execute(statement, args, options)
    for i, row in ipairs(rows) do
      rows[i] = self:_unmarshall(row)
    end
    return _, rows, err, page
  end

  local results, err = session:execute(statement, args, options)

  -- First, close the socket
  local socket_err = self:_close_session(session)
  if socket_err then
    return nil, socket_err
  end

  -- Handle unprepared queries
  if err and err.cassandra_err_code == cassandra_constants.error_codes.UNPREPARED then
    ngx.log(ngx.NOTICE, "Cassandra did not recognize prepared statement \""..cache_key.."\". Re-preparing it and re-trying the query. (Error: "..err..")")
    -- If the statement was declared unprepared, clear it from the cache, and try again.
    self._statements_cache[session_uniq_addr(session)][cache_key] = nil
    return self:_execute(query, args, options)
  elseif err then
    err = DaoError(err, error_types.DATABASE)
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

--- Perform "unique" check on a column.
-- Check that all fields marked with `unique` in the schema do not already exist
-- with the same value.
-- @param[type=table] t Key/value representation of the entity
-- @param[type=boolean] is_update If true, we ignore an identical value if the row containing it is the one we are trying to update.
-- @treturn boolean True if all unique fields are not already present, false if any already exists with the same value.
-- @treturn table A key/value table of all columns (as keys) having values already in the database.
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

--- Perform "foreign" check on a column.
-- Check all fields marked with `foreign` in the schema have an existing parent row.
-- @param[type=table] t Key/value representation of the entity
-- @treturn boolean True if all fields marked as foreign have a parent row.
-- @treturn table A key/value table of all columns (as keys) not having a parent row.
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

-- Add a delete hook on a parent DAO of a foreign row.
-- The delete hook will basically "cascade delete" all foreign rows of a parent row.
-- @see cassandra/factory.lua ':load_daos()'
-- @param[type=string] foreign_dao_name Name of the parent DAO
-- @param[type=string] foreign_column Name of the foreign column
-- @param[type=string] parent_column Name of the parent column identifying the parent row
function BaseDao:add_delete_hook(foreign_dao_name, foreign_column, parent_column)

  -- The actual delete hook
  -- @param[type=table] deleted_primary_key The value of the deleted row's primary key
  -- @treturn boolean True if success, false otherwise
  -- @treturn table A DAOError in case of error
  local delete_hook = function(deleted_primary_key)
    local foreign_dao = self._factory[foreign_dao_name]
    local select_args = {
      [foreign_column] = deleted_primary_key[parent_column]
    }

    -- Iterate over all rows with the foreign key and delete them.
    -- Rows need to be deleted by PRIMARY KEY, and we only have the value of the foreign key, hence we need
    -- to retrieve all rows with the foreign key, and then delete them, identifier by their own primary key.
    local select_q, columns = query_builder.select(foreign_dao._table, select_args, foreign_dao._column_family_details )
    for rows, err in foreign_dao:execute(select_q, columns, select_args, {auto_paging = true}) do
      if err then
        return false, err
      end
      for _, row in ipairs(rows) do
        local ok_del_foreign_row, err = foreign_dao:delete(row)
        if not ok_del_foreign_row then
          return false, err
        end
      end
    end

    return true
  end

  table.insert(self._cascade_delete_hooks, delete_hook)
end

return BaseDao
