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

local table_remove = table.remove
local error_types = constants.DATABASE_ERROR_TYPES

--- Base DAO
-- @section base_dao

local BaseDao = Object:extend()

--- Public interface.
-- Public methods developers can use in Kong core or in any plugin.
-- @section public

local function page_iterator(self, session, query, args, query_options)
  local iter = session:execute(query, args, query_options)
  return function(query, previous_rows)
    local rows, err, page = iter(query, previous_rows)
    if rows == nil or err ~= nil then
      session:set_keep_alive()
    else
      for i, row in ipairs(rows) do
        rows[i] = self:_unmarshall(row)
      end
    end
    return rows, err, page
  end, query
end

--- Execute a query.
-- This method should be called with the proper **args** formatting (as an array).
-- See `execute()` for building this parameter.
-- @see execute
-- @param query Plain string CQL query.
-- @param[type=table] args (Optional) Arguments to the query, as an array. Simply passed to lua-cassandra `execute()`.
-- @param[type=table] query_options (Optional) Options to give to lua-cassandra `execute()` query_options.
-- @param[type=string] keyspace (Optional) Override the keyspace for this query if specified.
-- @treturn table If the result consists of ROWS, a table with an array of unmarshalled rows and a `next_page` property if the results has a `paging_state`. If the result is of type "VOID", a boolean representing the success of the query. Otherwise, the raw result as given by lua-cassandra.
-- @treturn table An error if any during the execution.
function BaseDao:execute(query, args, query_options, keyspace)
  local options = self._factory:get_session_options()
  if keyspace then
    options.keyspace = keyspace
  end

  local session, err = cassandra.spawn_session(options)
  if not session then
    return nil, DaoError(err, constants.DATABASE_ERROR_TYPES.DATABASE)
  end

  if query_options and query_options.auto_paging then
    return page_iterator(self, session, query, args, query_options)
  end

  local results, err = session:execute(query, args, query_options)
  if err then
    err = DaoError(err, constants.DATABASE_ERROR_TYPES.DATABASE)
  end

  -- First, close the session (and underlying sockets)
  session:set_keep_alive()

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

--- Children DAOs interface.
-- Those methds are to be used in any child DAO and will perform the named operations
-- the entity they represent.
-- @section inherited

---
-- Insert a row in the defined column family (defined by the **_table** attribute).
-- Perform schema validation, 'UNIQUE' checks, 'FOREIGN' checks.
-- @see check_unique_fields
-- @see check_foreign_fields
-- @param[table=table] t A table representing the entity to insert.
-- @treturn table Inserted entity or nil.
-- @treturn table Error if any during the execution.
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
  local _, stmt_err = self:build_args_and_execute(insert_q, columns, self:_marshall(t))
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
-- @treturn table Updated entity or nil.
-- @treturn table Error if any during the execution.
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
        t_no_primary_key[k] = cassandra.unset
      end
    end
  end

  local update_q, columns = query_builder.update(self._table, t_no_primary_key, t_primary_key)

  local _, stmt_err = self:build_args_and_execute(update_q, columns, self:_marshall(t))
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
  local data, err = self:build_args_and_execute(select_q, where_columns, t_primary_key)

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
-- @param[type=string] paging_state Start page from given offset. See lua-cassandra's related `execute()` option.
-- @treturn table An array (of possible length 0) of entities as the result of the query
-- @treturn table An error if any
-- @treturn boolean A boolean indicating if the 'ALLOW FILTERING' clause was needed by the query
function BaseDao:find_by_keys(where_t, page_size, paging_state)
  local select_q, where_columns, filtering = query_builder.select(self._table, where_t, self._column_family_details)
  local res, err = self:build_args_and_execute(select_q, where_columns, where_t, {
    page_size = page_size,
    paging_state = paging_state
  })

  return res, err, filtering
end

---
-- Retrieve the number of rows in the related column family matching a possible 'WHERE' clause.
-- @param[type=table] where_t (Optional) columns/values table by which to count entities.
-- @param[type=string] paging_state Start page from given offset. It'll be passed along to lua-cassandra `execute()` query_options.
-- @treturn number The number of rows matching the specified criteria.
-- @treturn table An error if any.
-- @treturn boolean A boolean indicating if the 'ALLOW FILTERING' clause was needed by the query.
function BaseDao:count_by_keys(where_t, paging_state)
  local count_q, where_columns, filtering = query_builder.count(self._table, where_t, self._column_family_details)
  local res, err = self:build_args_and_execute(count_q, where_columns, where_t, {
    paging_state = paging_state
  })
  if err then
    return nil, err
  end

  return (#res >= 1 and table_remove(res, 1).count or 0), nil, filtering
end

---
-- Retrieve a page of rows from the related column family.
-- @param[type=number] page_size Size of the page to retrieve (number of rows). The default is the default value from lua-cassandra.
-- @param[type=string] paging_state Start page from given offset. It'll be passed along to lua-cassandra `execute()` query_options.
-- @return return values of find_by_keys()
-- @see find_by_keys
function BaseDao:find(page_size, paging_state)
  return self:find_by_keys(nil, page_size, paging_state)
end

---
-- Delete the row with PRIMARY KEY from the configured table (**_table** attribute).
-- @param[table=table] where_t A table containing the PRIMARY KEY (columns/values) of the row to delete
-- @treturn boolean True if deleted, false if otherwise or not found.
-- @treturn table Error if any during the query execution or the cascade delete hook.
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
  local results, err = self:build_args_and_execute(delete_q, where_columns, where_t)
  if err then
    return false, err
  end

  -- Delete successful, trigger cascade delete hooks if any.
  local foreign_err
  for _, hook in ipairs(self.cascade_delete_hooks) do
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
-- @return Return values of execute().
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

  self.properties = properties
  self.cascade_delete_hooks = {}
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
-- @local
-- Build the array of arguments to pass to lua-cassandra's `execute()` method.
-- Note:
--   Since this method only accepts an ordered list, we build this list from
--   the entity `t` and an (ordered) array of parameters for a query, taking
--   into account special cassandra values (uuid, timestamps, NULL).
-- @param[type=table] schema A schema with type properties to encode specific values.
-- @param[type=table] t Values to bind to a statement.
-- @param[type=table] parameters An ordered list of parameters.
-- @treturn table An ordered list of values to pass to lua-cassandra `execute()` args.
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
      arg = cassandra.unset
    end

    table.insert(args_to_bind, arg)
  end

  return args_to_bind, errors
end

---
-- Bind a table of arguments to a query depending on the entity's schema,
-- and then execute the query via `execute()`.
-- @param[type=string] query The query to execute.
-- @param[type=table] columns A list of column names where each value indicates the column of the value at the same index in `args_to_bind`.
-- @param[type=table] args_to_bind Key/value table of arguments to bind.
-- @param[type=table] query_options Options to pass to lua-cassandra `execute()` query_options.
-- @return return values of `execute()`.
-- @see _execute
function BaseDao:build_args_and_execute(query, columns, args_to_bind, query_options)
  -- Build args array if operation has some
  local args
  if columns and args_to_bind then
    local errors
    args, errors = encode_cassandra_args(self._schema, args_to_bind, columns)
    if errors then
      return nil, DaoError(errors, error_types.INVALID_TYPE)
    end
  end

  return self:execute(query, args, query_options)
end

--- Perform "unique" check on a column.
-- Check that all fields marked with `unique` in the schema do not already exist
-- with the same value.
-- @param[type=table] t Key/value representation of the entity
-- @param[type=boolean] is_update If true, ignore an identical value if the row containing it is the one we are trying to update.
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
-- @param[type=table] t Key/value representation of the entity.
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
-- @see cassandra/factory.lua `load_daos()`.
-- @param[type=string] foreign_dao_name Name of the parent DAO.
-- @param[type=string] foreign_column Name of the foreign column.
-- @param[type=string] parent_column Name of the parent column identifying the parent row.
function BaseDao:add_delete_hook(foreign_dao_name, foreign_column, parent_column)

  -- The actual delete hook.
  -- @param[type=table] deleted_primary_key The value of the deleted row's primary key.
  -- @treturn boolean True if success, false otherwise.
  -- @treturn table A DAOError in case of error.
  local delete_hook = function(deleted_primary_key)
    local foreign_dao = self._factory[foreign_dao_name]
    local select_args = {
      [foreign_column] = deleted_primary_key[parent_column]
    }

    -- Iterate over all rows with the foreign key and delete them.
    -- Rows need to be deleted by PRIMARY KEY, and we only have the value of the foreign key, hence we need
    -- to retrieve all rows with the foreign key, and then delete them, identifier by their own primary key.
    local select_q, columns = query_builder.select(foreign_dao._table, select_args, foreign_dao._column_family_details )
    for rows, err in foreign_dao:build_args_and_execute(select_q, columns, select_args, {auto_paging = true}) do
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

  table.insert(self.cascade_delete_hooks, delete_hook)
end

return BaseDao
