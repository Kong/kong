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
-- @copyright Copyright 2016-2018 Kong Inc. All rights reserved.
-- @license [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
-- @module kong.dao

local Object = require "kong.vendor.classic"
local utils = require "kong.tools.utils"
local Errors = require "kong.dao.errors"
local schemas_validation = require "kong.dao.schemas_validation"
local workspaces = require "kong.workspaces"
local rbac = require "kong.rbac"

local workspaceable = workspaces.get_workspaceable_relations()
local apply_unique_per_ws = workspaces.apply_unique_per_ws
local resolve_shared_entity_id = workspaces.resolve_shared_entity_id
local remove_ws_prefix = workspaces.remove_ws_prefix
local get_workspaces = workspaces.get_workspaces

local fmt    = string.format
local ipairs = ipairs
local pairs = pairs
local new_tab
do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function(narr, nrec) return {} end
  end
end


local RANDOM_VALUE = utils.random_string()

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

local function check_utf8(tbl, arg_n)
  for k, v in pairs(tbl) do
    if not utils.validate_utf8(v) then
      tbl[k] = RANDOM_VALUE -- Force a random string
    end
  end
end

local function ret_error(db_name, res, err, ...)
  if type(err) == "table" then
    err.db_name = db_name
  elseif type(err) == "string" then
    local e = Errors.db(err)
    e.db_name = db_name
    err = tostring(e)
  end

  return res, err, ...
end


local DAO = Object:extend()

DAO.ret_error = ret_error

--- Instanciate a DAO.
-- The DAO Factory is responsible for instanciating DAOs for each entity.
-- This method is only documented for clarity.
-- @param db An instance of the underlying database object (`cassandra_db` or `postgres_db`)
-- @param model_mt The related model metatable. Such metatables contain, among other things, validation methods.
-- @param schema The schema of the entity for which this DAO is instanciated. The schema contains crucial informations about how to interact with the database (fields type, table name, etc...)
-- @param constraints A table of contraints built by the DAO Factory. Such constraints are mostly useful for databases without support for foreign keys. SQL databases handle those contraints natively.
-- @return self
function DAO:new(db, model_mt, schema, constraints)
  self.db = db
  self.model_mt = model_mt
  self.schema = schema
  self.table = schema.table
  self.constraints = constraints
end

function DAO:cache_key_ws(workspace, arg1, arg2, arg3, arg4, arg5)
  return fmt("%s:%s:%s:%s:%s:%s:%s", self.table,
    arg1 == nil and "" or arg1,
    arg2 == nil and "" or arg2,
    arg3 == nil and "" or arg3,
    arg4 == nil and "" or arg4,
    arg5 == nil and "" or arg5,
    workspace == nil and "" or workspace.id)
end

function DAO:cache_key(arg1, arg2, arg3, arg4, arg5)
  local workspace = get_workspaces()[1]

  -- Entities that are not workspaceable do not need to be cached with
  -- the current workspace. No matter what ws is the request (if any)
  -- comming from.
  local workspaceable = self.schema.workspaceable
  if not workspaceable then
    workspace = nil
  end

  return fmt("%s:%s:%s:%s:%s:%s:%s", self.table,
             arg1 == nil and "" or arg1,
             arg2 == nil and "" or arg2,
             arg3 == nil and "" or arg3,
             arg4 == nil and "" or arg4,
             arg5 == nil and "" or arg5,
             workspace == nil and "" or workspace.id)
end

function DAO:entity_cache_key(entity)
  local schema    = self.schema
  local cache_key = schema.cache_key

  if not cache_key then
    return
  end

  local n = #cache_key
  local keys = new_tab(n, 0)
  keys.n = n

  for i = 1, n do
    keys[i] = entity[cache_key[i]]
  end

  return self:cache_key_ws(nil, utils.unpack(keys))
end

--- Insert a row.
-- Insert a given Lua table as a row in the related table.
-- @param[type=table] tbl Table to insert as a row.
-- @param[type=table] options Options to use for this insertion. (`ttl`: Time-to-live for this row, in seconds, `quiet`: does not send event)
-- @treturn table res A table representing the insert row (with fields created during the insertion).
-- @treturn table err If an error occured, a table describing the issue.
function DAO:insert(tbl, options)
  options = options or {}
  check_arg(tbl, 1, "table")
  check_arg(options, 2, "table")

  -- deep copy so that the resolve_shared_entity_id call doesn't
  -- modify the tbl argument
  local tbl = utils.deep_copy(tbl)

  local model = self.model_mt(tbl)
  local ok, err = model:validate {dao = self}
  if not ok then
    return ret_error(self.db.name, nil, err)
  end

  local workspace, err = apply_unique_per_ws(self.table, model,
                                             workspaceable[self.table])
  if err then
    return ret_error(self.db.name, nil, err)
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
  remove_ws_prefix(self.table, res)
  if not err and workspace then
    local err_rel = workspaces.add_entity_relation(self.table, res, workspace)
    if err_rel then
      local _, err = self:delete(res)
      if err then
        return ret_error(self.db.name, nil, err)
      end
      return ret_error("workspace_entity", nil, err_rel)
    end

    -- if entity just created is an rbac user, create its corresponding role
    if res and self.table == "rbac_users" then
      local _, err = rbac.create_default_role(res)
      if err then
        ret_error("failed to create default role for '" .. res.name .. "'", nil, err)
      end
    end

    -- if entity was created, insert it in the user's default role
    if res then
      local _, err = rbac.add_default_role_entity_permission(res, self.table)
      if err then
        return ret_error("failed to add entity permissions to current user",
                         nil, err)
      end
    end
  end

  if not err and not options.quiet then
    if self.events then
      local _, err = self.events.post_local("dao:crud", "create", {
        schema    = self.schema,
        operation = "create",
        entity    = res,
      })
      if err then
        ngx.log(ngx.ERR, "could not propagate CRUD operation: ", err)
      end
    end
  end
  return ret_error(self.db.name, res, err)
end

--- Find a row.
-- Find a row by its given, mandatory primary key. All other fields are ignored.
-- @param[type=table] tbl A table containing the primary key field(s) for this row.
-- @treturn table row The row, or nil if none could be found.
-- @treturn table err If an error occured, a table describing the issue.
function DAO:find(tbl)
  check_arg(tbl, 1, "table")
  check_utf8(tbl, 1)

  -- deep copy so that the resolve_shared_entity_id call doesn't
  -- modify the tbl argument
  local tbl = utils.deep_copy(tbl)

  local model = self.model_mt(tbl)
  if not model:has_primary_keys() then
    error("Missing PRIMARY KEY field", 2)
  end

  local primary_keys, _, _, err = model:extract_keys()
  if err then
    return ret_error(self.db.name, nil, Errors.schema(err))
  end

  local table_name = self.table
  local constraints = workspaceable[table_name]
  local _, err = resolve_shared_entity_id(table_name, tbl, constraints)
  if err then
    return ret_error(self.db.name, nil, Errors.schema(err))
  end

  local r = rbac.validate_entity_operation(primary_keys, table_name)
  if not r then
    ret_error(self.db.name, nil, Errors.forbidden({
      username = ngx.ctx.rbac.user.name,
      action = rbac.readable_action(ngx.ctx.rbac.action)
    }))
  end

  local row, err = self.db:find(self.table, self.schema, primary_keys)
  if err then
    ret_error(self.db.name, row, err)
  end
  remove_ws_prefix(self.schema.table, row)

  return ret_error(self.db.name, row, err)
end

--- Find all rows.
-- Find all rows in the table, eventually matching the values in the given fields.
-- @param[type=table] tbl (optional) A table containing the fields and values to search for.
-- @treturn rows An array of rows.
-- @treturn table err If an error occured, a table describing the issue.
function DAO:find_all(tbl, include_ws)
  local skip_rbac
  local table_name = self.table
  local constraints = workspaceable[table_name]

  -- deep copy so that the resolve_shared_entity_id call doesn't
  -- modify the tbl argument
  local tbl = utils.deep_copy(tbl)

  if tbl ~= nil then
    check_arg(tbl, 1, "table")
    check_utf8(tbl, 1)

    skip_rbac = tbl.__skip_rbac
    tbl.__skip_rbac = nil

    check_not_empty(tbl, 1)

    local ok, err = schemas_validation.is_schema_subset(tbl, self.schema)
    if not ok then
      return ret_error(self.db.name, nil, Errors.schema(err))
    end

    -- run with assumption that there is only one workspace
    -- in scope and entity was created in same workspace. So
    -- if filter has any unique key, just prefix it with workspace name
    local params = utils.deep_copy(tbl)
    apply_unique_per_ws(self.table, params, constraints)
    local rows, err = self.db:find_all(self.table, params, self.schema)
    if err then
      return ret_error(self.db.name, nil, Errors.schema(err))
    end

    if rows and #rows > 0 then
      for _, row in ipairs(rows) do
        remove_ws_prefix(table_name, row, include_ws)
      end

      if skip_rbac ~= true then
        rows = rbac.narrow_readable_entities(table_name, rows)
      end
      return ret_error(self.db.name, rows, err)
    end

    -- now search in the relationship table
    local ok, err = resolve_shared_entity_id(table_name, tbl, constraints)
    if err then
      return ret_error(self.db.name, nil, Errors.schema(err))
    end

    if not ok then
      tbl = params
    end
  end

  local rows, err = self.db:find_all(self.table, tbl, self.schema)
  if err then
    return ret_error(self.db.name, nil, Errors.schema(err))
  end

  for _, row in ipairs(rows) do
    remove_ws_prefix(table_name, row, include_ws)
  end

  if skip_rbac ~= true then
    rows = rbac.narrow_readable_entities(table_name, rows)
  end

  return ret_error(self.db.name, rows, err)
end

--- Find a paginated set of rows.
-- Find a pginated set of rows eventually matching the values in the given fields.
-- @param[type=table] tbl (optional) A table containing the fields and values to filter for.
-- @param page_offset Offset at which to resume pagination.
-- @param page_size Size of the page to retrieve (number of rows).
-- @treturn table rows An array of rows.
-- @treturn table err If an error occured, a table describing the issue.
function DAO:find_page(tbl, page_offset, page_size, options)
  options = options or {}
  local table_name = self.table
  local constraints = workspaceable[table_name]

   -- deep copy so that the resolve_shared_entity_id call doesn't
   -- modify the tbl argument
   local tbl = utils.deep_copy(tbl)

   if tbl ~= nil then
    check_arg(tbl, 1, "table")
    check_not_empty(tbl, 1)
    local ok, err = schemas_validation.is_schema_subset(tbl, self.schema)
    if not ok then
      return ret_error(self.db.name, nil, Errors.schema(err))
    end

     local _, err = resolve_shared_entity_id(table_name, tbl, constraints)
     if err then
       return ret_error(self.db.name, nil, Errors.schema(err))
     end
  end

  if page_size == nil then
    page_size = 100
  end

  check_arg(page_size, 3, "number")

  local rows, err, offset = self.db:find_page(self.table, tbl, page_offset,
                                              page_size, self.schema)
  if err then
    return ret_error(self.db.name, nil, err)
  end
  for _, row in ipairs(rows) do
    remove_ws_prefix(self.schema.table, row)
  end

  if not options.__skip_rbac then
    rows = rbac.narrow_readable_entities(self.schema.table, rows)
  end

  return ret_error(self.db.name, rows, err, offset)
end

--- Count the number of rows.
-- Count the number of rows matching the given values.
-- @param[type=table] tbl (optional) A table containing the fields and values to filter for.
-- @treturn number count The total count of rows matching the given filter, or total count of rows if no filter was given.
-- @treturn table err If an error occured, a table describing the issue.
function DAO:count(tbl)
  local table_name = self.table
  local constraints = workspaceable[table_name]

  -- deep copy so that the resolve_shared_entity_id call doesn't
  -- modify the tbl argument
  local tbl = utils.deep_copy(tbl)

  if tbl ~= nil then
    check_arg(tbl, 1, "table")
    check_not_empty(tbl, 1)
    local ok, err = schemas_validation.is_schema_subset(tbl, self.schema)
    if not ok then
      return ret_error(self.db.name, nil, Errors.schema(err))
    end

    local _, err = resolve_shared_entity_id(table_name, tbl, constraints)
    if err then
      return ret_error(self.db.name, nil, Errors.schema(err))
    end
  end

  if tbl ~= nil and next(tbl) == nil then
    tbl = nil
  end

  return ret_error(self.db.name, self.db:count(self.table, tbl, self.schema))
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
        elseif new[col][f_k] == ngx.null then
          new[col][f_k] = nil
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
-- @param[type=table] options Options to use for this update. (`full`: performs a full update of the entity, `quiet`: does not send event).
-- @treturn table res A table representing the updated entity.
-- @treturn table err If an error occured, a table describing the issue.
function DAO:update(tbl, filter_keys, options)
  options = options or {}
  check_arg(tbl, 1, "table")
  check_not_empty(tbl, 1)
  check_arg(filter_keys, 2, "table")
  check_not_empty(filter_keys, 2)
  check_arg(options, 3, "table")

  -- deep copy so that the resolve_shared_entity_id call doesn't
  -- modify the tbl argument
  local tbl = utils.deep_copy(tbl)

  for k, v in pairs(filter_keys) do
    if tbl[k] == nil then
      tbl[k] = v
    end
  end

  local model = self.model_mt(tbl)
  local ok, err = model:validate {dao = self, update = true, full_update = options.full}
  if not ok then
    return ret_error(self.db.name, nil, err)
  end

  local primary_keys, values, nils, err = model:extract_keys()
  if err then
    return ret_error(self.db.name, nil, Errors.schema(err))
  end

  local old, err = self.db:find(self.table, self.schema, primary_keys)
  if err then
    return ret_error(self.db.name, nil, err)
  elseif old == nil then
    return
  end

  local constraints = workspaceable[self.table]
  -- XXX: rethink the first condition. as maybe adding __skip_rbac is
  -- more fine grained and useful than this shotgun surgery
  if not options.__skip_rbac and
    not rbac.is_system_table(self.table) and
    not rbac.validate_entity_operation(old, self.table) then
    return ret_error(self.db.name, nil, Errors.forbidden({
      username = ngx.ctx.rbac.user.name,
      action = rbac.readable_action(ngx.ctx.rbac.action)
    }))
  end

  if not options.full then
    fix(old, values, self.schema)
  end

  apply_unique_per_ws(self.table, values, constraints)

  local res, err = self.db:update(self.table, self.schema, self.constraints, primary_keys, values, nils, options.full, model, options)
  if err then
    return ret_error(self.db.name, nil, err)
  elseif res then
    remove_ws_prefix(self.table, res)
    local err = workspaces.update_entity_relation(self.table, res)
    if err then
      return ret_error(self.db.name, nil, err)
    end
    if not options.quiet then
      remove_ws_prefix(self.table, old)
      if self.events then
        local _, err = self.events.post_local("dao:crud", "update", {
          schema     = self.schema,
          operation  = "update",
          entity     = res,
          old_entity = old,
        })
        if err then
          ngx.log(ngx.ERR, "could not propagate CRUD operation: ", err)
        end
      end
    end
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
function DAO:delete(tbl, options)
  options = options or {}
  check_arg(tbl, 1, "table")
  check_arg(options, 2, "table")

  -- deep copy so that the resolve_shared_entity_id call doesn't
  -- modify the tbl argument
  local tbl = utils.deep_copy(tbl)

  local ws = get_workspaces()[1]
  local constraints = workspaceable[self.table]
  apply_unique_per_ws(self.schema.table, tbl, constraints)

  local model = self.model_mt(tbl)
  if not model:has_primary_keys() then
    error("Missing PRIMARY KEY field", 2)
  end

  local primary_keys, _, _, err = model:extract_keys()
  if err then
    return ret_error(self.db.name, nil, Errors.schema(err))
  end

  -- Find associated entities
  local associated_entites = {}
  if self.constraints.cascade ~= nil then
    for f_entity, cascade in pairs(self.constraints.cascade) do
      local f_fetch_keys = {[cascade.f_col] = tbl[cascade.col]}
      local rows, err = self.db:find_all(cascade.table, f_fetch_keys, cascade.schema)
      if err then
        return ret_error(self.db.name, nil, err)
      end
      associated_entites[cascade.table] = {
        schema = cascade.schema,
        entities = rows
      }
    end
  end

  if not options.__skip_rbac and
    (not rbac.validate_entity_operation(primary_keys, self.table) or
     not rbac.check_cascade(associated_entites, ngx.ctx.rbac))  then
    return ret_error(self.db.name, nil, Errors.forbidden({
      username = ngx.ctx.rbac.user.name,
      action = rbac.readable_action(ngx.ctx.rbac.action)
    }))
  end

  local row, err = self.db:delete(self.table, self.schema, primary_keys, self.constraints)
  if not err and row ~= nil and not options.quiet then
    remove_ws_prefix(self.table, row)
    if self.events then
      local _, err = self.events.post_local("dao:crud", "delete", {
        schema    = self.schema,
        operation = "delete",
        entity    = row,
      })
      if err then
        ngx.log(ngx.ERR, "could not propagate CRUD operation: ", err)
      end
    end

    -- Also propagate the deletion for the associated entities
    for k, v in pairs(associated_entites) do
      for _, entity in ipairs(v.entities) do
        remove_ws_prefix(k, entity)
        if self.events then
          local _, err = self.events.post_local("dao:crud", "delete", {
            schema    = v.schema,
            operation = "delete",
            entity    = entity,
          })
          if err then
            ngx.log(ngx.ERR, "could not propagate CRUD operation: ", err)
          end
        end

        if ws then
          local err = workspaces.delete_entity_relation(k, entity)
          if err then
            ngx.log(ngx.ERR,
              "could not delete entity relationship with workspace: ",
              err)
          end

          local err = rbac.delete_role_entity_permission(k, entity)
          if err then
            ngx.log(ngx.ERR, "could not delete entity relationship with role: ",
              err)
          end
        end
      end
    end
  end
  if not err and ws then
    local err = workspaces.delete_entity_relation(self.table, tbl)
    if err then
      ngx.log(ngx.ERR,
        "could not delete entity relationship with workspace: ",
        err)
    end

    local err = rbac.delete_role_entity_permission(self.table, tbl)
    if err then
      ngx.log(ngx.ERR, "could not delete entity relationship with role: ",
        err)
    end
  end
  return ret_error(self.db.name, row, err)
end

function DAO:run_with_ws_scope(ws_scope, cb, ...)
  local old_ws = ngx.ctx.workspaces
  ngx.ctx.workspaces = ws_scope
  local res, err = cb(self, ...)
  ngx.ctx.workspaces = old_ws
  return res, err
end

function DAO:truncate()
  return ret_error(self.db.name, self.db:truncate_table(self.table))
end

return DAO
