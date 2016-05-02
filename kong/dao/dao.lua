--- Operates over entities of a given type in a database table.
-- An instance of this class is to be instanciated for each entity, and can interact
-- with the table representing the entity in the database.
--
-- Instanciations of this class are managed by the DAO Factory.
--
-- This class provides an abstraction for various databases (PostgreSQL, Cassandra)
-- and is responsible for propagating clustering events related to data invalidation,
-- as well as foreign constraints when the underlying database does not support them
-- (as with Cassandra).
-- @module kong.dao

local Object = require "classic"
local Errors = require "kong.dao.errors"
local schemas_validation = require "kong.dao.schemas_validation"
local event_types = require("kong.core.events").TYPES

local function check_arg(arg, arg_n, exp_type)
  if type(arg) ~= exp_type then
    local info = debug.getinfo(2)
    local err = string.format("bad argument #%d to '%s' (%s expected, got %s)",
                              arg_n, info.name, exp_type, type(arg))
    error(err, 3)
  end
end

local function check_not_empty(tbl, arg_n)
  if next(tbl) == nil then
    local info = debug.getinfo(2)
    local err = string.format("bad argument #%d to '%s' (expected table to not be empty)",
                              arg_n, info.name)
    error(err, 3)
  end
end

-- Publishes an event, if an event handler has been specified.
-- Currently this propagates the events cluster-wide.
-- @param[type=string] type The event type to publish
-- @param[type=table] data_t The payload to publish in the event
local function event(self, type, table, schema, data_t)
  if self.events_handler then
    if schema.marshall_event then
      data_t = schema.marshall_event(schema, data_t)
    else
      data_t = {}
    end

    local payload = {
      collection = table,
      primary_key = schema.primary_key,
      type = type,
      entity = data_t
    }

    self.events_handler:publish(self.events_handler.TYPES.CLUSTER_PROPAGATE, payload)
  end
end

local DAO = Object:extend()

--- Instanciate a DAO.
-- The DAO Factory is responsible for instanciating DAOs for each entity.
-- This method is only documented for clarity.
-- @param db An instance of the underlying database object (`cassandra_db` or `postgres_db`)
-- @param model_mt The related model metatable. Such metatables contain, among other things, validation methods.
-- @param schema The schema of the entity for which this DAO is instanciated. The schema contains crucial informations about how to interact with the database (fields type, table name, etc...)
-- @param constraints A table of contraints built by the DAO Factory. Such constraints are mostly useful for databases without support for foreign keys. SQL databases handle those contraints natively.
-- @param events_handler Instance of the events propagation class, used to propagate data invalidation events through the cluster.
-- @return self
function DAO:new(db, model_mt, schema, constraints, events_handler)
  self.db = db
  self.model_mt = model_mt
  self.schema = schema
  self.table = schema.table
  self.constraints = constraints
  self.events_handler = events_handler
end

--- Insert a row.
-- Insert a given Lua table as a row in the related table.
-- @param[type=table] tbl Table to insert as a row.
-- @param[type=table] options Options to use for this insertion. (`ttl`: Time-to-live for this row, in seconds)
-- @treturn table res A table representing the insert row (with fields created during the insertion).
-- @treturn table err If an error occured, a table describing the issue.
function DAO:insert(tbl, options)
  check_arg(tbl, 1, "table")

  local model = self.model_mt(tbl)
  local ok, err = model:validate {dao = self}
  if not ok then
    return nil, err
  end

  for col, field in pairs(model.__schema.fields) do
    if field.dao_insert_value and model[col] == nil then
      local f = self.db.dao_insert_values[field.type]
      if f then
        model[col] = f()
      end
    end
  end

  local res, err = self.db:insert(self.table, self.schema, model, self.constraints, options)
  if not err then
    event(self, event_types.ENTITY_CREATED, self.table, self.schema, res)
  end
  return res, err
end

--- Find a row.
-- Find a row by its given, mandatory primary key. All other fields are ignored.
-- @param[type=table] tbl A table containing the primary key field(s) for this row.
-- @treturn table row The row, or nil if none could be found.
-- @treturn table err If an error occured, a table describing the issue.
function DAO:find(tbl)
  check_arg(tbl, 1, "table")

  local model = self.model_mt(tbl)
  if not model:has_primary_keys() then
    error("Missing PRIMARY KEY field", 2)
  end

  local primary_keys, _, _, err = model:extract_keys()
  if err then
    return nil, Errors.schema(err)
  end

  return self.db:find(self.table, self.schema, primary_keys)
end

--- Find all rows.
-- Find all rows in the table, eventually matching the values in the given fields.
-- @param[type=table] tbl (optional) A table containing the fields and values to search for.
-- @treturn rows An array of rows.
-- @treturn table err If an error occured, a table describing the issue.
function DAO:find_all(tbl)
  if tbl ~= nil then
    check_arg(tbl, 1, "table")
    check_not_empty(tbl, 1)
    local ok, err = schemas_validation.is_schema_subset(tbl, self.schema)
    if not ok then
      return nil, Errors.schema(err)
    end
  end

  return self.db:find_all(self.table, tbl, self.schema)
end

--- Find a paginated set of rows.
-- Find a pginated set of rows eventually matching the values in the given fields.
-- @param[type=table] tbl (optional) A table containing the fields and values to filter for.
-- @param page_offset Offset at which to resume pagination.
-- @param page_size Size of the page to retrieve (number of rows).
-- @treturn table rows An array of rows.
-- @treturn table err If an error occured, a table describing the issue.
function DAO:find_page(tbl, page_offset, page_size)
   if tbl ~= nil then
    check_arg(tbl, 1, "table")
    check_not_empty(tbl, 1)
    local ok, err = schemas_validation.is_schema_subset(tbl, self.schema)
    if not ok then
      return nil, Errors.schema(err)
    end
  end

  if page_size == nil then
    page_size = 100
  end

  check_arg(page_size, 3, "number")

  return self.db:find_page(self.table, tbl, page_offset, page_size, self.schema)
end

--- Count the number of rows.
-- Count the number of rows matching the given values.
-- @param[type=table] tbl (optional) A table containing the fields and values to filter for.
-- @treturn number count The total count of rows matching the given filter, or total count of rows if no filter was given.
-- @treturn table err If an error occured, a table describing the issue.
function DAO:count(tbl)
  if tbl ~= nil then
    check_arg(tbl, 1, "table")
    check_not_empty(tbl, 1)
    local ok, err = schemas_validation.is_schema_subset(tbl, self.schema)
    if not ok then
      return nil, Errors.schema(err)
    end
  end

  if tbl ~= nil and next(tbl) == nil then
    tbl = nil
  end

  return self.db:count(self.table, tbl, self.schema)
end

local function fix(old, new, schema)
  for col, field in pairs(schema.fields) do
    if old[col] ~= nil and new[col] ~= nil and field.schema ~= nil then
      local f_schema, err
      if type(field.schema) == "function" then
        f_schema, err = field.schema(old)
        if err then
          error(err)
        end
      else
        f_schema = field.schema
      end
      for f_k in pairs(f_schema.fields) do
        if new[col][f_k] == nil and old[col][f_k] ~= nil then
          new[col][f_k] = old[col][f_k]
        end
      end

      fix(old[col], new[col], f_schema)
    end
  end
end

--- Update a row.
-- Update a row in the related table. Performe a partial update by default (only fields in `tbl` will)
-- be updated. If asked, can perform a "full" update, replacing the entire entity (assuming it is valid)
-- with the one specified in `tbl` at once.
-- @param[type=table] tbl A table containing the new values for this row.
-- @param[type=table] filter_keys A table which must contain the primary key(s) to select the row to be updated.
-- @param[type=table] options Options to use for this update. (`full`: performs a full update of the entity).
-- @treturn table res A table representing the updated entity.
-- @treturn table err If an error occured, a table describing the issue.
function DAO:update(tbl, filter_keys, options)
  check_arg(tbl, 1, "table")
  check_not_empty(tbl, 1)
  check_arg(filter_keys, 2, "table")
  check_not_empty(filter_keys, 2)
  options = options or {}

  for k, v in pairs(filter_keys) do
    if tbl[k] == nil then
      tbl[k] = v
    end
  end

  local model = self.model_mt(tbl)
  local ok, err = model:validate {dao = self, update = true, full_update = options.full}
  if not ok then
    return nil, err
  end

  local primary_keys, values, nils, err = model:extract_keys()
  if err then
    return nil, Errors.schema(err)
  end

  local old, err = self.db:find(self.table, self.schema, primary_keys)
  if err then
    return nil, err
  elseif old == nil then
    return
  end

  if not options.full then
    fix(old, values, self.schema)
  end

  local res, err = self.db:update(self.table, self.schema, self.constraints, primary_keys, values, nils, options.full, model, options)
  if err then
    return nil, err
  elseif res then
    event(self, event_types.ENTITY_UPDATED, self.table, self.schema, old)
    return setmetatable(res, nil)
  end
end

--- Delete a row.
-- Delete a row in table related to this instance. Also deletes all rows with a relashionship to the deleted row
-- (via foreign key relations). For SQL databases such as PostgreSQL, the underlying implementation
-- leverages "FOREIGN KEY" constraints, but for others such as Cassandra, such operations are executed
-- manually.
-- @param[type=table] tbl A table containing the primary key field(s) for this row.
-- @treturn table row A table representing the deleted row
-- @treturn table err If an error occured, a table describing the issue.
function DAO:delete(tbl)
  check_arg(tbl, 1, "table")

  local model = self.model_mt(tbl)
  if not model:has_primary_keys() then
    error("Missing PRIMARY KEY field", 2)
  end

  local primary_keys, _, _, err = model:extract_keys()
  if err then
    return nil, Errors.schema(err)
  end

  -- Find associated entities
  local associated_entites = {}
  if self.constraints.cascade ~= nil then
    for f_entity, cascade in pairs(self.constraints.cascade) do
      local f_fetch_keys = {[cascade.f_col] = tbl[cascade.col]}
      local rows, err = self.db:find_all(cascade.table, f_fetch_keys, cascade.schema)
      if err then
        return nil, err
      end
      associated_entites[cascade.table] = {
        schema = cascade.schema,
        entities = rows
      }
    end
  end

  local row, err = self.db:delete(self.table, self.schema, primary_keys, self.constraints)
  if not err and row ~= nil then
    event(self, event_types.ENTITY_DELETED, self.table, self.schema, row)

    -- Also propagate the deletion for the associated entities
    for k, v in pairs(associated_entites) do
      for _, entity in ipairs(v.entities) do
        event(self, event_types.ENTITY_DELETED, k, v.schema, entity)
      end
    end
  end
  return row, err
end

return DAO
