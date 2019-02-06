local cjson = require "cjson"
local iteration = require "kong.db.iteration"


local setmetatable = setmetatable
local tostring     = tostring
local require      = require
local ipairs       = ipairs
local concat       = table.concat
local error        = error
local pairs        = pairs
local floor        = math.floor
local null         = ngx.null
local type         = type
local next         = next
local log          = ngx.log
local fmt          = string.format

local workspaces = require "kong.workspaces"
local ws_helper  = require "kong.workspaces.helper"
local rbac       = require "kong.rbac"


local workspaceable = workspaces.get_workspaceable_relations()


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


local function validate_size_type(size)
  if type(size) ~= "number" then
    error("size must be a number", 3)
  end

  return true
end


local function validate_size_value(size)
  if floor(size) ~= size or
           size < 1 or
           size > 1000 then
    return nil, "size must be an integer between 1 and 1000"
  end

  return true
end


local function validate_offset_type(offset)
  if type(offset) ~= "string" then
    error("offset must be a string", 3)
  end

  return true
end


local function validate_entity_type(entity)
  if type(entity) ~= "table" then
    error("entity must be a table", 3)
  end

  return true
end


local function validate_primary_key_type(primary_key)
  if type(primary_key) ~= "table" then
    error("primary_key must be a table", 3)
  end

  return true
end


local function validate_foreign_key_type(foreign_key)
  if type(foreign_key) ~= "table" then
    error("foreign_key must be a table", 3)
  end

  return true
end


local function validate_unique_type(unique_value, name, field)
  if type(unique_value) ~= "table" and (field.type == "array"  or
                                        field.type == "set"    or
                                        field.type == "map"    or
                                        field.type == "record" or
                                        field.type == "foreign") then
    error(fmt("%s must be a table", name), 3)

  elseif type(unique_value) ~= "string" and field.type == "string" then
    error(fmt("%s must be a string", name), 3)

  elseif type(unique_value) ~= "number" and (field.type == "number" or
    field.type == "integer") then
    error(fmt("%s must be a number", name), 3)

  elseif type(unique_value) ~= "boolean" and field.type == "boolean" then
    error(fmt("%s must be a boolean", name), 3)
  end

  return true
end


local function validate_options_type(options)
  if type(options) ~= "table" then
    error("options must be a table when specified", 3)
  end

  return true
end


local function validate_options_value(options, schema, context)
  local errors = {}

  if schema.ttl == true and options.ttl ~= nil then
    if context ~= "insert" and
       context ~= "update" and
       context ~= "upsert" then
      errors.ttl = fmt("option can only be used with inserts, updates and upserts, not with '%ss'",
                       tostring(context))

    elseif floor(options.ttl) ~= options.ttl or
                 options.ttl < 0 or
                 options.ttl > 100000000 then
      -- a bit over three years maximum to make it more safe against
      -- integer overflow (time() + ttl)
      errors.ttl = "must be an integer between 0 and 100000000"
    end

  elseif schema.ttl ~= true and options.ttl ~= nil then
    errors.ttl = fmt("cannot be used with '%s'", schema.name)
  end

  if next(errors) then
    return nil, errors
  end

  return true
end


local function check_update(self, key, entity, options, name)
  local entity_to_update, err, read_before_write =
    self.schema:process_auto_fields(entity, "update")
  if not entity_to_update then
    local err_t = self.errors:schema_violation(err)
    return nil, nil, tostring(err_t), err_t
  end

  local rbw_entity
  if read_before_write then
    local err, err_t
    if name then
      -- XXX EE: This changes the behavior of finding entities by a
      -- field from ce to EE. For EE, call resolve_shared_entity_id
      -- that pivots through workspace_entities
      rbw_entity, err = ws_helper.resolve_shared_entity_id(self.table_name,
        {[name] = key}, workspaceable[self.schema.name])
      -- rbw_entity, err, err_t = self.strategy:select_by_field(name, key, options)
    else
       rbw_entity, err, err_t = self.strategy:select(key, options)
    end
    if err then
      return nil, nil, err, err_t
    end

    ws_helper.remove_ws_prefix(self.schema.name, rbw_entity)
    if rbw_entity then
      entity_to_update = self.schema:merge_values(entity_to_update, rbw_entity)
    else
      local err_t = name
                    and self.errors:not_found_by_field({ [name] = key })
                    or  self.errors:not_found(key)
      return nil, nil, tostring(err_t), err_t
    end
  end

  local ok, errors = self.schema:validate_update(entity_to_update)
  if not ok then
    local err_t = self.errors:schema_violation(errors)
    return nil, nil, tostring(err_t), err_t
  end

  if options ~= nil then
    ok, errors = validate_options_value(options, self.schema, "update")
    if not ok then
      local err_t = self.errors:invalid_options(errors)
      return nil, nil, tostring(err_t), err_t
    end
  end

  if self.schema.cache_key and #self.schema.cache_key > 1 then
    entity_to_update.cache_key = self:cache_key(entity_to_update)
  end

  return entity_to_update, rbw_entity
end


local function find_cascade_delete_entities(self, entity)
  local constraints = self.schema:get_constraints()
  local entries = {}
  local pk = self.schema:extract_pk_values(entity)
  for _, constraint in ipairs(constraints) do
    if constraint.on_delete ~= "cascade" then
      goto continue
    end

    local dao = self.db.daos[constraint.schema.name]
    local method = "each_for_" .. constraint.field_name
    for row, err in dao[method](dao, pk) do
      if not row then
        log(ERR, "[db] failed to traverse entities for cascade-delete: ", err)
        break
      end

      table.insert(entries, { dao = dao, entity = row })
    end

    ::continue::
  end

  return entries
end


local function propagate_cascade_delete_events(entries)
  for _, entry in ipairs(entries) do
    entry.dao:post_crud_event("delete", entry.entity)
  end
end


local function generate_foreign_key_methods(schema)
  local methods = {}

  for name, field in schema:each_field() do
    if field.type == "foreign" then
      local page_method_name = "page_for_" .. name
      methods[page_method_name] = function(self, foreign_key, size, offset, options)
        validate_foreign_key_type(foreign_key)

        if size ~= nil then
          validate_size_type(size)
        end

        if offset ~= nil then
          validate_offset_type(offset)
        end

        if options ~= nil then
          validate_options_type(options)
        end

        local ok, errors = self.schema:validate_field(field, foreign_key)
        if not ok then
          local err_t = self.errors:invalid_primary_key(errors)
          return nil, tostring(err_t), err_t
        end

        if size ~= nil then
          local err
          ok, err = validate_size_value(size)
          if not ok then
            local err_t = self.errors:invalid_size(err)
            return nil, tostring(err_t), err_t
          end

        else
          size = 100
        end

        if options ~= nil then
          ok, errors = validate_options_value(options, schema, "select")
          if not ok then
            local err_t = self.errors:invalid_options(errors)
            return nil, tostring(err_t), err_t
          end
        end

        local strategy = self.strategy

        local rows, err_t, new_offset = strategy[page_method_name](strategy,
                                                                   foreign_key,
                                                                   size,
                                                                   offset,
                                                                   options)
        if not rows then
          return nil, tostring(err_t), err_t
        end

        local entities, err
        -- XXX check this
        entities, err, err_t = self:rows_to_entities(rows, options)
        if err then
          return nil, err, err_t
        end

        if options and not options.skip_rbac then
          local table_name = self.schema.name
          entities = rbac.narrow_readable_entities(table_name, entities)
        end

        return entities, nil, nil, new_offset
      end

      -- XXX EE: add new logic for workspaces here
      local each_method_name = "each_for_" .. name
      methods[each_method_name] = function(self, foreign_key, size, options)
        validate_foreign_key_type(foreign_key)

        if size ~= nil then
          validate_size_type(size)
        end

        if size ~= nil then
          local ok, err = validate_size_value(size)
          if not ok then
            local err_t = self.errors:invalid_size(err)
            return iteration.failed(tostring(err_t), err_t)
          end

        else
          size = 100
        end

        if options ~= nil then
          validate_options_type(options)
        end

        local ok, errors = self.schema:validate_primary_key(foreign_key)
        if not ok then
          local err_t = self.errors:invalid_primary_key(errors)
          return iteration.failed(tostring(err_t), err_t)
        end

        if options ~= nil then
          ok, errors = validate_options_value(options, schema, "select")
          if not ok then
            local err_t = self.errors:invalid_options(errors)
            return nil, tostring(err_t), err_t
          end
        end

        local strategy = self.strategy

        local pager = function(size, offset)
          return strategy[page_method_name](strategy, foreign_key, size, offset, options)
        end

        return iteration.by_row(self, pager, size)
      end

    elseif field.unique or schema.endpoint_key == name then
      methods["select_by_" .. name] = function(self, unique_value, options)
        validate_unique_type(unique_value, name, field)

        if options ~= nil then
          validate_options_type(options)
        end

        local ok, err = schema:validate_field(field, unique_value)
        if not ok then
          local err_t = self.errors:invalid_unique(name, err)
          return nil, tostring(err_t), err_t
        end

        if options ~= nil then
          local errors
          ok, errors = validate_options_value(options, schema, "select")
          if not ok then
            local err_t = self.errors:invalid_options(errors)
            return nil, tostring(err_t), err_t
          end
        end

        local params = { [name] = unique_value }
        local constraints = workspaceable[self.schema.name]
        ws_helper.apply_unique_per_ws(self.schema.name, params, constraints)

        local row, err_t = self.strategy:select_by_field(name, params[name], options)
        if err_t then
          return nil, tostring(err_t), err_t
        end

        if not row then
          local pk, err_t = ws_helper.resolve_shared_entity_id(self.schema.name,
                                                              { [name] = unique_value },
                                                               workspaceable[self.schema.name])
          if err_t then
            return nil, tostring(err_t), err_t
          end

          if pk then
            return self:select(pk, options)
          end

          return nil
        end

        if options and not options.skip_rbac then
          local r = rbac.validate_entity_operation(row, self.schema.name)
          if not r then
            local err_t = self.errors:unauthorized_operation({
              username = ngx.ctx.rbac.user.name,
              action = rbac.readable_action(ngx.ctx.rbac.action)
            })
            return nil, tostring(err_t), err_t
          end
        end

        if row then
          return self:row_to_entity(row, options)
        end
      end

      methods["update_by_" .. name] = function(self, unique_value, entity, options)
        validate_unique_type(unique_value, name, field)
        validate_entity_type(entity)

        if options ~= nil then
          validate_options_type(options)
        end

        local ok, err = schema:validate_field(field, unique_value)
        if not ok then
          local err_t = self.errors:invalid_unique(name, err)
          return nil, tostring(err_t), err_t
        end

        -- luacheck: ignore

        local entity_to_update, rbw_entity, err, err_t = check_update(self, unique_value,
                                                                      entity, options, name)
        if not entity_to_update then
          return nil, err, err_t
        end

        if err_t then
          return nil, tostring(err_t), err_t
        end

        -- XXX EE: This changes the behavior of finding entities by a
        -- field from ce to EE. For EE, call resolve_shared_entity_id
        -- that pivots through workspace_entities
        do
          local row, err = self:update({id = entity_to_update.id}, entity_to_update, options)
          if not err then
            return nil, tostring(err)
          end

          row, err, err_t = self:row_to_entity(row, options)
          if not row then
            return nil, err, err_t
          end

          self:post_crud_event("update", row, rbw_entity)
          return row
        end


        local row, err_t = self.strategy:update_by_field(name, unique_value,
                                                         entity_to_update, options)
        if not row then
          return nil, tostring(err_t), err_t
        end

        row, err, err_t = self:row_to_entity(row, options)
        if not row then
          return nil, err, err_t
        end

        self:post_crud_event("update", row, rbw_entity)

        return row
      end

      -- XXX EE: add new logic for workspaces here
      methods["upsert_by_" .. name] = function(self, unique_value, entity, options)
        validate_unique_type(unique_value, name, field)
        validate_entity_type(entity)

        if options ~= nil then
          validate_options_type(options)
        end

        local pk, err_t = ws_helper.resolve_shared_entity_id(self.schema.name,
                                                            { [name] = unique_value },
                                                             workspaceable[self.schema.name])

        if err_t then
          return nil, tostring(err_t), err_t
        end
        if pk then
          return self:upsert(pk)
        end

        local ok, err = schema:validate_field(field, unique_value)
        if not ok then
          local err_t = self.errors:invalid_unique(name, err)
          return nil, tostring(err_t), err_t
        end

        local entity_to_upsert, err = self.schema:process_auto_fields(entity, "upsert")
        if not entity_to_upsert then
          local err_t = self.errors:schema_violation(err)
          return nil, tostring(err_t), err_t
        end

        entity_to_upsert[name] = unique_value
        local errors
        ok, errors = self.schema:validate_upsert(entity_to_upsert)
        if not ok then
          local err_t = self.errors:schema_violation(errors)
          return nil, tostring(err_t), err_t
        end
        if self.schema.cache_key and #self.schema.cache_key > 1 then
          entity_to_upsert.cache_key = self:cache_key(entity_to_upsert)
        end
        entity_to_upsert[name] = nil

        if options ~= nil then
          ok, errors = validate_options_value(options, schema, "upsert")
          if not ok then
            local err_t = self.errors:invalid_options(errors)
            return nil, tostring(err_t), err_t
          end
        end

        if not rbac.validate_entity_operation(entity_to_upsert, self.schema.name) then
          local err_t = self.errors:unauthorized_operation({
            username = ngx.ctx.rbac.user.name,
            action = rbac.readable_action(ngx.ctx.rbac.action)
          })
          return nil, tostring(err_t), err_t
        end

        local constraints = workspaceable[self.schema.name]
        local params = {[name] = unique_value}

        local workspace, err_t = ws_helper.apply_unique_per_ws(self.schema.name, params, constraints)
        if err then
          return nil, tostring(err_t), err_t
        end

        local row, err_t = self.strategy:upsert_by_field(name, params[name],
                                                         entity_to_upsert, options)
        if not row then
          return nil, tostring(err_t), err_t
        end

        row, err, err_t = self:row_to_entity(row, options)
        if not row then
          return nil, err, err_t
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

          -- if entity was created, insert it in the user's default role
          if row then
            local _, err = rbac.add_default_role_entity_permission(row, self.schema.name)
            if err then
              local err_t = self.errors:database_error("failed to add entity permissions to current user")
              return nil, tostring(err_t), err_t
            end
          end
        end

        self:post_crud_event("update", row)

        return row
      end

      methods["delete_by_" .. name] = function(self, unique_value, options)
        validate_unique_type(unique_value, name, field)

        local pk, err_t = ws_helper.resolve_shared_entity_id(self.schema.name,
                                                            { [name] = unique_value },
                                                            workspaceable[self.schema.name])
        if err_t then
          return nil, tostring(err_t), err_t
        end
        if pk then
          return self:delete(pk)
        end

        if options ~= nil then
          validate_options_type(options)
        end

        local ok, err = schema:validate_field(field, unique_value)
        if not ok then
          local err_t = self.errors:invalid_unique(name, err)
          return nil, tostring(err_t), err_t
        end

        if options ~= nil then
          local errors
          ok, errors = validate_options_value(options, schema, "delete")
          if not ok then
            local err_t = self.errors:invalid_options(errors)
            return nil, tostring(err_t), err_t
          end
        end

        local entity, err, err_t = self["select_by_" .. name](self, unique_value)
        if err then
          return nil, err, err_t
        end

        if not entity then
          return true
        end

        local cascade_entries = find_cascade_delete_entities(self, entity)

        local _
        _, err_t = self.strategy:delete_by_field(name, unique_value, options)
        if err_t then
          return nil, tostring(err_t), err_t
        end

        self:post_crud_event("delete", entity)
        propagate_cascade_delete_events(cascade_entries)

        return true
      end
    end
  end

  return methods
end


function _M.new(db, schema, strategy, errors)
  local fk_methods = generate_foreign_key_methods(schema)
  local super      = setmetatable(fk_methods, DAO)

  local self = {
    db       = db,
    schema   = schema,
    strategy = strategy,
    errors   = errors,
    super    = super,
  }

  if schema.dao then
    local custom_dao = require(schema.dao)
    for name, method in pairs(custom_dao) do
      self[name] = method
    end
  end

  return setmetatable(self, { __index = super })
end


function DAO:truncate()
  return self.strategy:truncate()
end


function DAO:select(primary_key, options)
  validate_primary_key_type(primary_key)

  if options ~= nil then
    validate_options_type(options)
  end

  local ok, errors = self.schema:validate_primary_key(primary_key)
  if not ok then
    local err_t = self.errors:invalid_primary_key(errors)
    return nil, tostring(err_t), err_t
  end

  if options ~= nil then
    ok, errors = validate_options_value(options, self.schema, "select")
    if not ok then
      local err_t = self.errors:invalid_options(errors)
      return nil, tostring(err_t), err_t
    end
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

  local row, err_t = self.strategy:select(primary_key, options)
  if err_t then
    return nil, tostring(err_t), err_t
  end

  if not row then
    return nil
  end

  if options and not options.skip_rbac then
    local r = rbac.validate_entity_operation(primary_key, self.schema.name)
    if not r then
      local err_t = self.errors:unauthorized_operation({
        username = ngx.ctx.rbac.user.name,
        action = rbac.readable_action(ngx.ctx.rbac.action)
      })
      return  nil, tostring(err_t), err_t
    end
  end

  return self:row_to_entity(row, options)
end


function DAO:page(size, offset, options)
  if size ~= nil then
    validate_size_type(size)
  end

  if offset ~= nil then
    validate_offset_type(offset)
  end

  if options ~= nil then
    validate_options_type(options)
  end

  if size ~= nil then
    local ok, err = validate_size_value(size)
    if not ok then
      local err_t = self.errors:invalid_size(err)
      return nil, tostring(err_t), err_t
    end

  else
    size = 100
  end

  if options ~= nil then
    local ok, errors = validate_options_value(options, self.schema, "select")
    if not ok then
      local err_t = self.errors:invalid_options(errors)
      return nil, tostring(err_t), err_t
    end
  end

  local rows, err_t, offset = self.strategy:page(size, offset, options)
  if err_t then
    return nil, tostring(err_t), err_t
  end

  local entities, err
  entities, err, err_t = self:rows_to_entities(rows, options)
  if not entities then
    return nil, err, err_t
  end

  if options and not options.skip_rbac then
    local table_name = self.schema.name
    entities = rbac.narrow_readable_entities(table_name, entities)
  end

  return entities, err, err_t, offset
end


function DAO:each(size, options)
  if size ~= nil then
    validate_size_type(size)
  end

  if options ~= nil then
    validate_options_type(options)
  end

  if size ~= nil then
    local ok, err = validate_size_value(size)
    if not ok then
      local err_t = self.errors:invalid_size(err)
      return nil, tostring(err_t), err_t
    end

  else
    size = 100
  end

  if options ~= nil then
    local ok, errors = validate_options_value(options, self.schema, "select")
    if not ok then
      local err_t = self.errors:invalid_options(errors)
      return nil, tostring(err_t), err_t
    end
  end

  local pager = function(size, offset, options)
    return self.strategy:page(size, offset, options)
  end

  return iteration.by_row(self, pager, size, options)
end


function DAO:insert(entity, options)
  validate_entity_type(entity)

  if options ~= nil then
    validate_options_type(options)
  end

  local entity_to_insert, err = self.schema:process_auto_fields(entity, "insert")
  if not entity_to_insert then
    local err_t = self.errors:schema_violation(err)
    return nil, tostring(err_t), err_t
  end

  local ok, errors = self.schema:validate_insert(entity_to_insert)
  if not ok then
    local err_t = self.errors:schema_violation(errors)
    return nil, tostring(err_t), err_t
  end

  if options ~= nil then
    ok, errors = validate_options_value(options, self.schema, "insert")
    if not ok then
      local err_t = self.errors:invalid_options(errors)
      return nil, tostring(err_t), err_t
    end
  end

  if self.schema.cache_key and #self.schema.cache_key > 1 then
    entity_to_insert.cache_key = self:cache_key(entity_to_insert)
  end

  local workspace, err_t = ws_helper.apply_unique_per_ws(self.schema.name, entity_to_insert,
                                                         workspaceable[self.schema.name])
  if err then
    return nil, tostring(err_t), err_t
  end

  local row, err_t = self.strategy:insert(entity_to_insert, options)
  if not row then
    return nil, tostring(err_t), err_t
  end

  row, err, err_t = self:row_to_entity(row, options)
  if not row then
    return nil, err, err_t
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

    -- if entity was created, insert it in the user's default role
    if row then
      local _, err = rbac.add_default_role_entity_permission(row, self.schema.name)
      if err then
        local err_t = self.errors:database_error("failed to add entity permissions to current user")
        return nil, tostring(err_t), err_t
      end
    end
  end

  self:post_crud_event("create", row)

  return row
end


function DAO:update(primary_key, entity, options)
  validate_primary_key_type(primary_key)
  validate_entity_type(entity)

  if options ~= nil then
    validate_options_type(options)
  end

  local ok, errors = self.schema:validate_primary_key(primary_key)
  if not ok then
    local err_t = self.errors:invalid_primary_key(errors)
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

  local entity_to_update, rbw_entity, err, err_t = check_update(self,
                                                                primary_key,
                                                                entity,
                                                                options)
  if not entity_to_update then
    return nil, err, err_t
  end

  if not rbac.validate_entity_operation(entity_to_update, self.schema.name) then
    local err_t = self.errors:unauthorized_operation({
      username = ngx.ctx.rbac.user.name,
      action = rbac.readable_action(ngx.ctx.rbac.action)
    })
    return nil, tostring(err_t), err_t
  end

  ws_helper.apply_unique_per_ws(self.schema.name, entity_to_update, constraints)

  local row, err_t = self.strategy:update(primary_key, entity_to_update, options)
  if not row then
    return nil, tostring(err_t), err_t
  end

  row, err, err_t = self:row_to_entity(row, options)
  if not row then
    return nil, err, err_t
  end

  if not err then
    local err_rel = workspaces.update_entity_relation(self.schema.name, row)
    if err_rel then
      return nil, tostring(err_rel), err_rel
    end
  end

  self:post_crud_event("update", row, rbw_entity)

  return row
end


-- XXX EE add workspaces
function DAO:upsert(primary_key, entity, options)
  validate_primary_key_type(primary_key)
  validate_entity_type(entity)

  if options ~= nil then
    validate_options_type(options)
  end

  local ok, errors = self.schema:validate_primary_key(primary_key)
  if not ok then
    local err_t = self.errors:invalid_primary_key(errors)
    return nil, tostring(err_t), err_t
  end

  local constraints = workspaceable[self.schema.name]
  local ok, err = ws_helper.validate_pk_exist(self.schema.name,
                                              primary_key, constraints)
  if err then
    local err_t = self.errors:database_error(err)
    return nil, tostring(err_t), err_t
  end

  local entity_to_upsert, err = self.schema:process_auto_fields(entity, "upsert")
  if not entity_to_upsert then
    local err_t = self.errors:schema_violation(err)
    return nil, tostring(err_t), err_t
  end

  ok, errors = self.schema:validate_upsert(entity_to_upsert)
  if not ok then
    local err_t = self.errors:schema_violation(errors)
    return nil, tostring(err_t), err_t
  end

  if options ~= nil then
    ok, errors = validate_options_value(options, self.schema, "upsert")
    if not ok then
      local err_t = self.errors:invalid_options(errors)
      return nil, tostring(err_t), err_t
    end
  end

  if self.schema.cache_key and #self.schema.cache_key > 1 then
    entity_to_upsert.cache_key = self:cache_key(entity_to_upsert)
  end

  if not rbac.validate_entity_operation(primary_key, self.schema.name) then
    local err_t = self.errors:unauthorized_operation({
      username = ngx.ctx.rbac.user.name,
      action = rbac.readable_action(ngx.ctx.rbac.action)
    })
    return nil, tostring(err_t), err_t
  end

  ws_helper.apply_unique_per_ws(self.schema.name, entity_to_upsert, constraints)

  local row, err_t = self.strategy:upsert(primary_key, entity_to_upsert, options)
  if not row then
    return nil, tostring(err_t), err_t
  end

  row, err, err_t = self:row_to_entity(row, options)
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


function DAO:delete(primary_key, options)
  validate_primary_key_type(primary_key)

  if options ~= nil then
    validate_options_type(options)
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

  local entity, err, err_t = self:select(primary_key)
  if err then
    return nil, err, err_t
  end

  if not entity then
    return true
  end

  if options ~= nil then
    ok, errors = validate_options_value(options, self.schema, "delete")
    if not ok then
      local err_t = self.errors:invalid_options(errors)
      return nil, tostring(err_t), err_t
    end
  end

  local cascade_entries = find_cascade_delete_entities(self, primary_key)

  local _
  _, err_t = self.strategy:delete(primary_key, options)
  if err_t then
    return nil, tostring(err_t), err_t
  end

  self:post_crud_event("delete", entity)
  propagate_cascade_delete_events(cascade_entries)

  return true
end


-- XXX EE check if needs workspaces logic
function DAO:select_by_cache_key(cache_key, options)
  local ck_definition = self.schema.cache_key
  if not ck_definition then
    error("entity does not have a cache_key defined", 2)
  end

  if type(cache_key) ~= "string" then
    cache_key = self:cache_key(cache_key)
  end

  if #ck_definition == 1 then
    return self["select_by_" .. ck_definition[1]](self, cache_key, options)
  end

  local row, err_t = self.strategy:select_by_field("cache_key", cache_key, options)
  if err_t then
    return nil, tostring(err_t), err_t
  end

  if not row then
    return nil
  end

  return self:row_to_entity(row, options)
end


function DAO:rows_to_entities(rows, options)
  local count = #rows
  if count == 0 then
    return setmetatable(rows, cjson.empty_array_mt)
  end

  local entities = new_tab(count, 0)

  for i = 1, count do
    local entity, err, err_t = self:row_to_entity(rows[i], options)
    if not entity then
      return nil, err, err_t
    end

    entities[i] = entity
  end

  return entities
end


function DAO:row_to_entity(row, options)
  if options ~= nil then
    validate_options_type(options)
  end

  local nulls = options and options.nulls

  local entity, errors = self.schema:process_auto_fields(row, "select", nulls)
  if not entity then
    local err_t = self.errors:schema_violation(errors)
    return nil, tostring(err_t), err_t
  end

  ws_helper.remove_ws_prefix(self.schema.name, entity, options and options.include_ws)

  return entity
end


function DAO:post_crud_event(operation, entity, old_entity)
  if self.events then
    local _, err = self.events.post_local("dao:crud", operation, {
      operation  = operation,
      schema     = self.schema,
      entity     = entity,
      old_entity = old_entity,
    })
    if err then
      log(ERR, "[db] failed to propagate CRUD operation: ", err)
    end
  end
end


function DAO:cache_key(key, arg2, arg3, arg4, arg5)

  -- Fast path: passing the cache_key/primary_key entries in
  -- order as arguments, this produces the same result as
  -- the generic code below, but building the cache key
  -- becomes a single string.format operation

  if type(key) == "string" then
    return fmt("%s:%s:%s:%s:%s:%s", self.schema.name,
               key == nil and "" or key,
               arg2 == nil and "" or arg2,
               arg3 == nil and "" or arg3,
               arg4 == nil and "" or arg4,
               arg5 == nil and "" or arg5)
  end

  -- Generic path: build the cache key from the fields
  -- listed in cache_key or primary_key

  if type(key) ~= "table" then
    error("key must be a string or an entity table", 2)
  end

  local values = new_tab(5, 0)
  values[1] = self.schema.name
  local source = self.schema.cache_key or self.schema.primary_key

  local i = 2
  for _, name in ipairs(source) do
    local field = self.schema.fields[name]
    local value = key[name]
    if field.type == "foreign" then
      -- FIXME extract foreign key, do not assume `id`
      if value == null or value == nil then
        value = ""
      else
        value = value.id
      end
    end
    values[i] = tostring(value)
    i = i + 1
  end
  for n = i, 6 do
    values[n] = ""
  end

  return concat(values, ":")
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


--[[
function DAO:load_translations(t)
  self.schema:load_translations(t)
end
--]]


return _M
