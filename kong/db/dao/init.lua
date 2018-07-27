local cjson     = require "cjson"


local setmetatable = setmetatable
local tostring     = tostring
local require      = require
local error        = error
local pairs        = pairs
local floor        = math.floor
local type         = type
local next         = next
local log          = ngx.log
local fmt          = string.format


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


local function generate_foreign_key_methods(schema)
  local methods = {}

  for name, field in schema:each_field() do
    if field.type == "foreign" then
      local method_name = "for_" .. name

      methods[method_name] = function(self, foreign_key, size, offset, options)
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

        local ok, errors = self.schema:validate_primary_key(foreign_key)
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

        local rows, err_t, new_offset = strategy[method_name](strategy,
                                                              foreign_key,
                                                              size, offset)
        if not rows then
          return nil, tostring(err_t), err_t
        end

        local entities, err
        entities, err, err_t = self:rows_to_entities(rows)
        if err then
          return nil, err, err_t
        end

        return entities, nil, nil, new_offset
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

        local row, err_t = self.strategy:select_by_field(name, unique_value)
        if err_t then
          return nil, tostring(err_t), err_t
        end

        if not row then
          return nil
        end

        return self:row_to_entity(row)
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

        local entity_to_update, err = self.schema:process_auto_fields(entity, "update")
        if not entity_to_update then
          local err_t = self.errors:schema_violation(err)
          return nil, tostring(err_t), err_t
        end

        local errors
        ok, errors = self.schema:validate_update(entity_to_update)
        if not ok then
          local err_t = self.errors:schema_violation(errors)
          return nil, tostring(err_t), err_t
        end

        if options ~= nil then
          ok, errors = validate_options_value(options, schema, "update")
          if not ok then
            local err_t = self.errors:invalid_options(errors)
            return nil, tostring(err_t), err_t
          end
        end

        local row, err_t = self.strategy:update_by_field(name, unique_value,
                                                         entity_to_update, options)
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

      methods["upsert_by_" .. name] = function(self, unique_value, entity, options)
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
        entity_to_upsert[name] = nil

        if options ~= nil then
          ok, errors = validate_options_value(options, schema, "upsert")
          if not ok then
            local err_t = self.errors:invalid_options(errors)
            return nil, tostring(err_t), err_t
          end
        end

        local row, err_t = self.strategy:upsert_by_field(name, unique_value,
                                                         entity_to_upsert, options)
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

      methods["delete_by_" .. name] = function(self, unique_value, options)
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

        local _

        _, err_t = self.strategy:delete_by_field(name, unique_value, options)
        if err_t then
          return nil, tostring(err_t), err_t
        end

        self:post_crud_event("delete", entity)

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

  local row, err_t = self.strategy:select(primary_key, options)
  if err_t then
    return nil, tostring(err_t), err_t
  end

  if not row then
    return nil
  end

  return self:row_to_entity(row)
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
  entities, err, err_t = self:rows_to_entities(rows)
  if not entities then
    return nil, err, err_t
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

  local next_row = self.strategy:each(size, options)

  return function()
    local err_t
    local row, err, page = next_row()
    if not row then
      if err then
        if type(err) == "table" then
          return nil, tostring(err), err
        end

        err_t = self.errors:database_error(err)
        return nil, tostring(err_t), err_t
      end

      return nil
    end

    row, err, err_t = self:row_to_entity(row)
    if not row then
      return nil, err, err_t
    end

    return row, nil, page
  end
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

  local row, err_t = self.strategy:insert(entity_to_insert, options)
  if not row then
    return nil, tostring(err_t), err_t
  end

  row, err, err_t = self:row_to_entity(row)
  if not row then
    return nil, err, err_t
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

  local entity_to_update, err = self.schema:process_auto_fields(entity, "update")
  if not entity_to_update then
    local err_t = self.errors:schema_violation(err)
    return nil, tostring(err_t), err_t
  end

  ok, errors = self.schema:validate_update(entity_to_update)
  if not ok then
    local err_t = self.errors:schema_violation(errors)
    return nil, tostring(err_t), err_t
  end

  if options ~= nil then
    ok, errors = validate_options_value(options, self.schema, "update")
    if not ok then
      local err_t = self.errors:invalid_options(errors)
      return nil, tostring(err_t), err_t
    end
  end

  local row, err_t = self.strategy:update(primary_key, entity_to_update, options)
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

  local row, err_t = self.strategy:upsert(primary_key, entity_to_upsert, options)
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


function DAO:delete(primary_key, options)
  validate_primary_key_type(primary_key)

  if options ~= nil then
    validate_options_type(options)
  end

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

  local _
  _, err_t = self.strategy:delete(primary_key, options)
  if err_t then
    return nil, tostring(err_t), err_t
  end

  self:post_crud_event("delete", entity)

  return true
end


function DAO:rows_to_entities(rows)
  local count = #rows
  if count == 0 then
    return setmetatable(rows, cjson.empty_array_mt)
  end

  local entities = new_tab(count, 0)

  for i = 1, count do
    local entity, err, err_t = self:row_to_entity(rows[i])
    if not entity then
      return nil, err, err_t
    end

    entities[i] = entity
  end

  return entities
end


function DAO:row_to_entity(row)
  local entity, errors = self.schema:process_auto_fields(row, "select")
  if not entity then
    local err_t = self.errors:schema_violation(errors)
    return nil, tostring(err_t), err_t
  end

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


function DAO:cache_key(arg1, arg2, arg3, arg4, arg5)
  return fmt("%s:%s:%s:%s:%s:%s",
             self.schema.name,
             arg1 == nil and "" or arg1,
             arg2 == nil and "" or arg2,
             arg3 == nil and "" or arg3,
             arg4 == nil and "" or arg4,
             arg5 == nil and "" or arg5)
end


return _M
