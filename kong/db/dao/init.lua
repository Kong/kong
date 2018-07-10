local cjson        = require "cjson"

local workspaces = require "kong.workspaces"
local ws_helper  = require "kong.workspaces.helper"
local rbac       = require "kong.rbac"


local workspaceable = workspaces.get_workspaceable_relations()

local setmetatable = setmetatable
local tonumber     = tonumber
local require      = require
local error        = error
local pairs        = pairs
local type         = type
local min          = math.min
local log          = ngx.log
local tostring     = tostring


local ERR          = ngx.ERR


local new_tab
do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function() return {} end
  end
end


local _M    = {}
local DAO   = {}
DAO.__index = DAO


local function generate_foreign_key_methods(self)
  local schema = self.schema

  for name, field in schema:each_field() do
    if field.type == "foreign" then
      local method_name = "for_" .. name

      self[method_name] = function(self, foreign_key, size, offset, options)
        options = options or {}
        if type(foreign_key) ~= "table" then
          error("foreign_key must be a table", 2)
        end

        if size ~= nil then
          if type(size) ~= "number" then
            error("size must be a number", 2)
          end

          if size < 0 then
            error("size must be a positive number", 2)
          end

          size = min(size, 1000)

        else
          size = 100
        end

        if offset ~= nil and type(offset) ~= "string" then
          error("offset must be a string", 2)
        end

        local ok, errors = self.schema:validate_primary_key(foreign_key)
        if not ok then
          local err_t = self.errors:invalid_primary_key(errors)
          return nil, tostring(err_t), err_t
        end

        local strategy = self.strategy

        local rows, err_t, new_offset = strategy[method_name](strategy,
                                                              foreign_key,
                                                              size, offset)
        if not rows then
          return nil, tostring(err_t), err_t
        end

        local entities, err, err_t = self:rows_to_entities(rows, options.include_ws)
        if err then
          return nil, err, err_t
        end

        if not options.skip_rbac then
          local table_name = self.schema.name
          entities = rbac.narrow_readable_entities(table_name, entities)
        end

        return entities, nil, nil, new_offset
      end

    elseif field.unique then
      local function validate_unique_value(unique_value)
        local ok, err = self.schema:validate_field(field, unique_value)
        if not ok then
          error("invalid argument '" .. name .. "' (" .. err .. ")", 3)
        end
      end

      self["select_by_" .. name] = function(self, unique_value, options)
        options = options or {}
        validate_unique_value(unique_value)

        local params = { [name] = unique_value }
        local constraints = workspaceable[self.schema.name]
        ws_helper.apply_unique_per_ws(self.schema.name, params, constraints)
        local row, err_t = self.strategy:select_by_field(name, params[name])
        if err_t then
          return nil, tostring(err_t), err_t
        end

        if not options.skip_rbac then
          local r = rbac.validate_entity_operation(row, self.schema.name)
          if not r then
            local err_t = self.errors:unauthorized_operation({
              username = ngx.ctx.rbac.user.name,
              action = rbac.readable_action(ngx.ctx.rbac.action)
            })
            return  nil, tostring(err_t), err_t
          end
        end

        if row then
          return self:row_to_entity(row)
        end
        local pk, err_t = ws_helper.resolve_shared_entity_id(self.schema.name,
                                                     { [name] = unique_value },
                                                             workspaceable[self.schema.name])
        if err_t then
          return nil, tostring(err_t), err_t
        end

        if pk then
          return self:select(pk, options)
        end
      end

      self["update_by_" .. name] = function(self, unique_value, entity)
        validate_unique_value(unique_value)

        local entity_to_update, err = self.schema:process_auto_fields(entity, "update")
        if not entity_to_update then
          local err_t = self.errors:schema_violation(err)
          return nil, tostring(err_t), err_t
        end

        local ok, errors = self.schema:validate_update(entity_to_update)
        if not ok then
          local err_t = self.errors:schema_violation(errors)
          return nil, tostring(err_t), err_t
        end

        local pk, err_t = ws_helper.resolve_shared_entity_id(self.schema.name,
                                                     { [name] = unique_value },
                                                             workspaceable[self.schema.name])
        if err_t then
          return nil, tostring(err_t), err_t
        end
        if pk then
          return self:update(pk, entity_to_update)
        end

        local row, err_t = self.strategy:update_by_field(name, unique_value,
                                                         entity_to_update)
        if not row then
          return nil, tostring(err_t), err_t
        end

        row, err, err_t = self:row_to_entity(row)
        if not row then
          return nil, err, err_t
        end

        self:post_crud_event("update", row)

        return row
      end

      self["delete_by_" .. name] = function(self, unique_value)
        validate_unique_value(unique_value)
        local pk, err_t = ws_helper.resolve_shared_entity_id(self.schema.name,
                                                     { [name] = unique_value },
                                                             workspaceable[self.schema.name])
        if err_t then
          return nil, tostring(err_t), err_t
        end

        if pk then
          return self:delete(pk)
        end

        -- if workspace present and pk is nil
        -- entity not found, return
        local ws_scope = workspaces.get_workspaces()
        if #ws_scope > 0 then
          return true
        end

        local _, err_t, entity = self.strategy:delete_by_field(name, unique_value)
        if err_t then
          return nil, tostring(err_t), err_t
        end

        self:post_crud_event("delete", entity)

        return true
      end
    end
  end
end


function _M.new(schema, strategy, errors)
  local self = {
    schema   = schema,
    strategy = strategy,
    errors   = errors,
  }

  if schema.dao then
    local custom_dao = require(schema.dao)
    for name, method in pairs(custom_dao) do
      self[name] = method
    end
  end

  generate_foreign_key_methods(self)

  return setmetatable(self, DAO)
end


function DAO:select(primary_key, options)
  options = options or {}
  if type(primary_key) ~= "table" then
    error("primary_key must be a table", 2)
  end

  local ok, errors = self.schema:validate_primary_key(primary_key)
  if not ok then
    local err_t = self.errors:invalid_primary_key(errors)
    return nil, tostring(err_t), err_t
  end

  local table_name = self.schema.name
  local constraints = workspaceable[table_name]
  local ok, err = ws_helper.validate_pk_exist(table_name, primary_key, constraints)
  if err then
    local err_t = self.errors:database_error(err)
    return nil, tostring(err_t), err_t
  end

  if not ok then
    return nil
  end

  local row, err_t = self.strategy:select(primary_key)
  if err_t then
    return nil, tostring(err_t), err_t
  end

  if not row then
    return nil
  end

  if not options.skip_rbac then
    local r = rbac.validate_entity_operation(primary_key, self.schema.name)
    if not r then
      local err_t = self.errors:unauthorized_operation({
        username = ngx.ctx.rbac.user.name,
        action = rbac.readable_action(ngx.ctx.rbac.action)
      })
      return  nil, tostring(err_t), err_t
    end
  end

  return self:row_to_entity(row, options.include_ws)
end


function DAO:page(size, offset, options)
  options = options or {}
  size = tonumber(size == nil and 100 or size)

  if not size then
    error("size must be a number", 2)
  end

  size = min(size, 1000)

  if size < 0 then
    error("size must be positive (> 0)", 2)
  end

  if offset ~= nil and type(offset) ~= "string" then
    error("offset must be a string", 2)
  end

  local rows, err_t, offset = self.strategy:page(size, offset)
  if err_t then
    return nil, tostring(err_t), err_t
  end

  local entities, err, err_t = self:rows_to_entities(rows, options.include_ws)
  if not entities then
    return nil, err, err_t
  end

  if not options.skip_rbac then
    local table_name = self.schema.name
    entities = rbac.narrow_readable_entities(table_name, entities)
  end

  return entities, err, err_t, offset
end


function DAO:each(size)
  size = tonumber(size == nil and 100 or size)

  if not size then
    error("size must be a number", 2)
  end

  size = min(size, 1000)

  if size < 0 then
    error("size must be positive (> 0)", 2)
  end

  local next_row = self.strategy:each(size)

  return function()
    local row, err_t, page = next_row()
    if not row then
      if err_t then
        return nil, tostring(err_t), err_t
      end

      return nil
    end

    local err
    row, err, err_t = self:row_to_entity(row)
    if not row then
      return nil, err, err_t
    end

    return row, nil, page
  end
end


function DAO:insert(entity)
  if type(entity) ~= "table" then
    error("entity must be a table", 2)
  end

  local entity_to_insert, err = self.schema:process_auto_fields(entity, "insert")
  if not entity_to_insert then
    local err_t = self.errors:schema_violation(err)
    return nil, tostring(err_t), err_t
  end

  local ok, errors = self.schema:validate(entity_to_insert)
  if not ok then
    local err_t = self.errors:schema_violation(errors)
    return nil, tostring(err_t), err_t
  end

  local workspace, err_t = ws_helper.apply_unique_per_ws(self.schema.name, entity_to_insert,
                                                         workspaceable[self.schema.name])
  if err then
    return nil, tostring(err_t), err_t
  end

  local row, err_t = self.strategy:insert(entity_to_insert)
  if not row then
    return nil, tostring(err_t), err_t
  end

  row, err, err_t = self:row_to_entity(row)
  if not row then
    return nil, err, err_t
  end

  -- if entity was created, insert it in the user's default role
  if workspaceable[self.schema.name] then
    local _, err = rbac.add_default_role_entity_permission(row.id, self.schema.name)
    if err then
      return nil, "failed to add entity permissions to current user"
    end
  end

  if not err and workspace then
    local err_rel = workspaces.add_entity_relation(self.schema.name, row, workspace)
    if err_rel then
      local _, err_t = self:delete(row)
      if err then
        return nil, tostring(err_t), err_t
      end
      return nil, tostring(err_rel), err_rel
    end
  end

  self:post_crud_event("create", row)

  return row
end


function DAO:update(primary_key, entity)
  if type(primary_key) ~= "table" then
    error("primary_key must be a table", 2)
  end

  if type(entity) ~= "table" then
    error("entity must be a table", 2)
  end

  local ok, errors = self.schema:validate_primary_key(primary_key)
  if not ok then
    local err_t = self.errors:invalid_primary_key(errors)
    return nil, tostring(err_t), err_t
  end

  local entity_to_update, err = self.schema:process_auto_fields(entity, "update")
  if not entity_to_update then
    local err_t = self.errors:schema_violation(err)
    return nil, tostring(err_t), err_t
  end

  local constraints = workspaceable[self.schema.name]
  local ok, err = ws_helper.validate_pk_exist(self.schema.name,
                                              primary_key, constraints)
  if err then
    local err_t = self.errors:database_error(err)
    return nil, tostring(err_t), err_t
  end

  if not ok then
    local err_t = self.errors:not_found(primary_key)
    return nil, tostring(err_t), err_t
  end

  local ok, errors = self.schema:validate_update(entity_to_update)
  if not ok then
    local err_t = self.errors:schema_violation(errors)
    return nil, tostring(err_t), err_t
  end

  if not rbac.validate_entity_operation(entity_to_update, self.schema.name) then
    local err_t = self.errors:unauthorized_operation({
      username = ngx.ctx.rbac.user.name,
      action = rbac.readable_action(ngx.ctx.rbac.action)
    })
    return nil, tostring(err_t), err_t
  end
  ws_helper.apply_unique_per_ws(self.schema.name, entity_to_update, constraints)

  local row, err_t = self.strategy:update(primary_key, entity_to_update)
  if not row then
    return nil, tostring(err_t), err_t
  end

  row, err, err_t = self:row_to_entity(row)
  if not row then
    return nil, err, err_t
  end

  if not err then
    local err_rel = workspaces.update_entity_relation(self.schema.name, row)
    if err_rel then
      return nil, tostring(err_rel), err_rel
    end
  end

  self:post_crud_event("update", row)

  return row
end


function DAO:delete(primary_key)
  if type(primary_key) ~= "table" then
    error("primary_key must be a table", 2)
  end

  local constraints = workspaceable[self.schema.name]
  local ok, err = ws_helper.validate_pk_exist(self.schema.name,
                                              primary_key, constraints)
  if err then
    local err_t = self.errors:database_error(err)
    return nil, tostring(err_t), err_t
  end

  if not ok then
    return true
  end

  ws_helper.apply_unique_per_ws(self.schema.name, primary_key, constraints)

  local ok, errors = self.schema:validate_primary_key(primary_key)
  if not ok then
    local err_t = self.errors:invalid_primary_key(errors)
    return nil, tostring(err_t), err_t
  end

  local _, err_t, entity = self.strategy:delete(primary_key)
  if err_t then
    return nil, tostring(err_t), err_t
  end

  self:post_crud_event("delete", entity)

  return true
end


function DAO:rows_to_entities(rows, include_ws)
  local count = #rows
  if count == 0 then
    return setmetatable(rows, cjson.empty_array_mt)
  end

  local entities = new_tab(count, 0)

  for i = 1, count do
    local entity, err, err_t = self:row_to_entity(rows[i], include_ws)
    if not entity then
      return nil, err, err_t
    end

    entities[i] = entity
  end

  return entities
end


function DAO:row_to_entity(row, include_ws)
  local entity, errors = self.schema:process_auto_fields(row, "select")
  if not entity then
    local err_t = self.errors:schema_violation(errors)
    return nil, tostring(err_t), err_t
  end

  ws_helper.remove_ws_prefix(self.schema.name, entity, include_ws)

  return entity
end


function DAO:post_crud_event(operation, entity)
  if self.events then
    local ok, err = self.events.post_local("dao:crud", operation, {
      operation = operation,
      schema    = self.schema,
      new_db    = true,
      entity    = entity,
    })
    if not ok then
      log(ERR, "[db] failed to propagate CRUD operation: ", err)
    end
  end

end


return _M
