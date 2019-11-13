local cjson = require "cjson"
local iteration = require "kong.db.iteration"
local utils = require "kong.tools.utils"
local defaults = require "kong.db.strategies.connector".defaults


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
local match        = string.match


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


local function validate_size_value(size, max)
  if floor(size) ~= size or
           size < 1 or
           size > max then
    return nil, "size must be an integer between 1 and " .. max
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


local function validate_foreign_key_is_single_primary_key(field)
  if #field.schema.primary_key > 1 then
    error("primary keys containing composite foreign keys " ..
          "are currently not supported", 3)
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


local function get_pagination_options(self, options)
  if options == nil then
    return {
      pagination = self.pagination,
    }
  end

  if type(options) ~= "table" then
    error("options must be a table when specified", 3)
  end

  options = utils.deep_copy(options, false)

  if type(options.pagination) == "table" then
    options.pagination = utils.table_merge(self.pagination, options.pagination)

  else
    options.pagination = self.pagination
  end

  return options
end


local function validate_options_value(self, options)
  local errors = {}
  local schema = self.schema

  if schema.ttl == true and options.ttl ~= nil then
    if floor(options.ttl) ~= options.ttl or
                 options.ttl < 0 or
                 options.ttl > 100000000 then
      -- a bit over three years maximum to make it more safe against
      -- integer overflow (time() + ttl)
      errors.ttl = "must be an integer between 0 and 100000000"
    end

  elseif schema.ttl ~= true and options.ttl ~= nil then
    errors.ttl = fmt("cannot be used with '%s'", schema.name)
  end

  if schema.fields.tags and options.tags ~= nil then
    if type(options.tags) ~= "table" then
      if not options.tags_cond then
        -- If options.tags is not a table and options.tags_cond is nil at the same time
        -- it means arguments.lua gets an invalid tags arg from the Admin API
        errors.tags = "invalid filter syntax"
      else
        errors.tags = "must be a table"
      end
    elseif #options.tags > 5 then
      errors.tags = "cannot query more than 5 tags"
    elseif not match(concat(options.tags), "^[%w%.%-%_~]+$") then
      errors.tags = "must only contain alphanumeric and '., -, _, ~' characters"
    elseif #options.tags > 1 and options.tags_cond ~= "and" and options.tags_cond ~= "or" then
      errors.tags_cond = "must be a either 'and' or 'or' when more than one tag is specified"
    end

  elseif schema.fields.tags == nil and options.tags ~= nil then
    errors.tags = fmt("cannot be used with '%s'", schema.name)
  end

  if options.pagination ~= nil then
    if type(options.pagination) ~= "table" then
      errors.pagination = "must be a table"

    else
      local page_size     = options.pagination.page_size
      local max_page_size = options.pagination.max_page_size

      if max_page_size == nil then
        max_page_size = self.pagination.max_page_size

      elseif type(max_page_size) ~= "number" then
        errors.pagination = {
          max_page_size = "must be a number",
        }

        max_page_size = self.pagination.max_page_size

      elseif floor(max_page_size) ~= max_page_size or max_page_size < 1 then
        errors.pagination = {
          max_page_size = "must be an integer greater than 0",
        }

        max_page_size = self.pagination.max_page_size
      end

      if page_size ~= nil then
        if type(page_size) ~= "number" then
          if not errors.pagination then
            errors.pagination = {
              page_size = "must be a number",
            }

          else
            errors.pagination.page_size = "must be a number"
          end

        elseif floor(page_size) ~= page_size
          or page_size < 1
          or page_size > max_page_size
        then
          if not errors.pagination then
            errors.pagination = {
              page_size = fmt("must be an integer between 1 and %d", max_page_size),
            }

          else
            errors.pagination.page_size = fmt("must be an integer between 1 and %d", max_page_size)
          end
        end
      end
    end
  end

  if next(errors) then
    return nil, errors
  end

  return true
end


local function resolve_foreign(self, entity)
  local errors = {}
  local has_errors

  for field_name, field in self.schema:each_field() do
    local schema = field.schema
    if field.type == "foreign" and schema.validate_primary_key then
      local value = entity[field_name]
      if value and value ~= null then
        if not schema:validate_primary_key(value, true) then
          local resolve_errors = {}
          local has_resolve_errors
          for unique_field_name, unique_field in schema:each_field() do
            if unique_field.unique or unique_field.endpoint_key then
              local unique_value = value[unique_field_name]
              if unique_value and unique_value ~= null and
                 schema:validate_field(unique_field, unique_value) then

                local dao = self.db[schema.name]
                local select = dao["select_by_" .. unique_field_name]
                local foreign_entity, err, err_t = select(dao, unique_value)
                if err_t then
                  return nil, err, err_t
                end

                if foreign_entity then
                  entity[field_name] = schema:extract_pk_values(foreign_entity)
                  break
                end

                resolve_errors[unique_field_name] = {
                  name   = unique_field_name,
                  value  = unique_value,
                  parent = schema.name,
                }

                has_resolve_errors = true
              end
            end
          end

          if has_resolve_errors then
            errors[field_name] = resolve_errors
            has_errors = true
          end
        end
      end
    end
  end

  if has_errors then
    local err_t = self.errors:foreign_keys_unresolved(errors)
    return nil, tostring(err_t), err_t
  end

  return true
end


local function check_insert(self, entity, options)
  local entity_to_insert, err = self.schema:process_auto_fields(entity, "insert")
  if not entity_to_insert then
    local err_t = self.errors:schema_violation(err)
    return nil, tostring(err_t), err_t
  end

  local ok, err, err_t = resolve_foreign(self, entity_to_insert)
  if not ok then
    return nil, err, err_t
  end

  local ok, errors = self.schema:validate_insert(entity_to_insert, entity)
  if not ok then
    local err_t = self.errors:schema_violation(errors)
    return nil, tostring(err_t), err_t
  end

  entity_to_insert, err = self.schema:transform(entity_to_insert, entity, "insert")
  if not entity_to_insert then
    err_t = self.errors:transformation_error(err)
    return nil, tostring(err_t), err_t
  end

  if options ~= nil then
    ok, errors = validate_options_value(self, options)
    if not ok then
      local err_t = self.errors:invalid_options(errors)
      return nil, tostring(err_t), err_t
    end
  end

  if self.schema.cache_key and #self.schema.cache_key > 1 then
    entity_to_insert.cache_key = self:cache_key(entity_to_insert)
  end

  return entity_to_insert
end


local function check_update(self, key, entity, options, name)
  local entity_to_update, err, read_before_write, check_immutable_fields =
    self.schema:process_auto_fields(entity, "update")
  if not entity_to_update then
    local err_t = self.errors:schema_violation(err)
    return nil, nil, tostring(err_t), err_t
  end

  local rbw_entity
  if read_before_write then
    local err, err_t
    if name then
       rbw_entity, err, err_t = self["select_by_" .. name](self, key, options)
    else
       rbw_entity, err, err_t = self:select(key, options)
    end
    if err then
      return nil, nil, err, err_t
    end

    if rbw_entity and check_immutable_fields then
      local ok, errors = self.schema:validate_immutable_fields(entity_to_update, rbw_entity)

      if not ok then
        local err_t = self.errors:schema_violation(errors)
        return nil, nil, tostring(err_t), err_t
      end
    end

    if rbw_entity then
      entity_to_update = self.schema:merge_values(entity_to_update, rbw_entity)
    else
      local err_t = name
                    and self.errors:not_found_by_field({ [name] = key })
                    or  self.errors:not_found(key)
      return nil, nil, tostring(err_t), err_t
    end
  end

  local ok, err, err_t = resolve_foreign(self, entity_to_update)
  if not ok then
    return nil, err, err_t
  end

  local ok, errors = self.schema:validate_update(entity_to_update, entity, rbw_entity)
  if not ok then
    local err_t = self.errors:schema_violation(errors)
    return nil, nil, tostring(err_t), err_t
  end

  entity_to_update, err = self.schema:transform(entity_to_update, entity, "update")
  if not entity_to_update then
    err_t = self.errors:transformation_error(err)
    return nil, nil, tostring(err_t), err_t
  end

  if options ~= nil then
    ok, errors = validate_options_value(self, options)
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


local function check_upsert(self, entity, options, name, value)
  local entity_to_upsert, err = self.schema:process_auto_fields(entity, "upsert")
  if not entity_to_upsert then
    local err_t = self.errors:schema_violation(err)
    return nil, tostring(err_t), err_t
  end

  if name then
    entity_to_upsert[name] = value
  end

  local ok, err, err_t = resolve_foreign(self, entity_to_upsert)
  if not ok then
    return nil, err, err_t
  end

  local ok, errors = self.schema:validate_upsert(entity_to_upsert, entity)
  if not ok then
    local err_t = self.errors:schema_violation(errors)
    return nil, tostring(err_t), err_t
  end

  if name then
    entity_to_upsert[name] = nil
  end

  entity_to_upsert, err = self.schema:transform(entity_to_upsert, entity, "upsert")
  if not entity_to_upsert then
    err_t = self.errors:transformation_error(err)
    return nil, tostring(err_t), err_t
  end

  if options ~= nil then
    local ok, errors = validate_options_value(self, options)
    if not ok then
      local err_t = self.errors:invalid_options(errors)
      return nil, tostring(err_t), err_t
    end
  end

  if self.schema.cache_key and #self.schema.cache_key > 1 then
    entity_to_upsert.cache_key = self:cache_key(entity_to_upsert)
  end

  return entity_to_upsert
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


local function propagate_cascade_delete_events(entries, options)
  for _, entry in ipairs(entries) do
    entry.dao:post_crud_event("delete", entry.entity, nil, options)
  end
end


local function generate_foreign_key_methods(schema)
  local methods = {}

  for name, field in schema:each_field() do
    local field_is_foreign = field.type == "foreign"
    if field_is_foreign then
      validate_foreign_key_is_single_primary_key(field)

      local page_method_name = "page_for_" .. name
      methods[page_method_name] = function(self, foreign_key, size, offset, options)
        validate_foreign_key_type(foreign_key)

        if size ~= nil then
          validate_size_type(size)
        end

        if offset ~= nil then
          validate_offset_type(offset)
        end

        options = get_pagination_options(self, options)

        local ok, errors = self.schema:validate_field(field, foreign_key)
        if not ok then
          local err_t = self.errors:invalid_primary_key(errors)
          return nil, tostring(err_t), err_t
        end

        if size ~= nil then
          local err
          ok, err = validate_size_value(size, options.pagination.max_page_size)
          if not ok then
            local err_t = self.errors:invalid_size(err)
            return nil, tostring(err_t), err_t
          end

        else
          size = options.pagination.page_size
        end

        ok, errors = validate_options_value(self, options)
        if not ok then
          local err_t = self.errors:invalid_options(errors)
          return nil, tostring(err_t), err_t
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
        entities, err, err_t = self:rows_to_entities(rows, options)
        if err then
          return nil, err, err_t
        end

        return entities, nil, nil, new_offset
      end

      local each_method_name = "each_for_" .. name
      methods[each_method_name] = function(self, foreign_key, size, options)
        validate_foreign_key_type(foreign_key)

        if size ~= nil then
          validate_size_type(size)
        end

        options = get_pagination_options(self, options)

        if size ~= nil then
          local ok, err = validate_size_value(size, options.pagination.max_page_size)
          if not ok then
            local err_t = self.errors:invalid_size(err)
            return iteration.failed(tostring(err_t), err_t)
          end

        else
          size = options.pagination.page_size
        end

        local ok, errors = schema:validate_field(field, foreign_key)
        if not ok then
          local err_t = self.errors:invalid_primary_key(errors)
          return iteration.failed(tostring(err_t), err_t)
        end

        ok, errors = validate_options_value(self, options)
        if not ok then
          local err_t = self.errors:invalid_options(errors)
          return nil, tostring(err_t), err_t
        end

        local strategy = self.strategy

        local pager = function(size, offset, options)
          return strategy[page_method_name](strategy, foreign_key, size, offset, options)
        end

        return iteration.by_row(self, pager, size, options)
      end
    end

    if field.unique or schema.endpoint_key == name then
      methods["select_by_" .. name] = function(self, unique_value, options)
        validate_unique_type(unique_value, name, field)

        if options ~= nil then
          validate_options_type(options)
        end

        local ok, errors = schema:validate_field(field, unique_value)
        if not ok then
          if field_is_foreign then
            local err_t = self.errors:invalid_foreign_key(errors)
            return nil, tostring(err_t), err_t
          end

          local err_t = self.errors:invalid_unique(name, errors)
          return nil, tostring(err_t), err_t
        end

        if options ~= nil then
          ok, errors = validate_options_value(self, options)
          if not ok then
            local err_t = self.errors:invalid_options(errors)
            return nil, tostring(err_t), err_t
          end
        end

        local row, err_t = self.strategy:select_by_field(name, unique_value, options)
        if err_t then
          return nil, tostring(err_t), err_t
        end

        if not row then
          return nil
        end

        return self:row_to_entity(row, options)
      end

      methods["update_by_" .. name] = function(self, unique_value, entity, options)
        validate_unique_type(unique_value, name, field)
        validate_entity_type(entity)

        if options ~= nil then
          validate_options_type(options)
        end

        local ok, errors = schema:validate_field(field, unique_value)
        if not ok then
          if field_is_foreign then
            local err_t = self.errors:invalid_foreign_key(errors)
            return nil, tostring(err_t), err_t
          end

          local err_t = self.errors:invalid_unique(name, errors)
          return nil, tostring(err_t), err_t
        end

        local entity_to_update, rbw_entity, err, err_t = check_update(self, unique_value,
                                                                      entity, options, name)
        if not entity_to_update then
          return nil, err, err_t
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

        self:post_crud_event("update", row, rbw_entity, options)

        return row
      end

      methods["upsert_by_" .. name] = function(self, unique_value, entity, options)
        validate_unique_type(unique_value, name, field)
        validate_entity_type(entity)

        if options ~= nil then
          validate_options_type(options)
        end

        local ok, errors = schema:validate_field(field, unique_value)
        if not ok then
          if field_is_foreign then
            local err_t = self.errors:invalid_foreign_key(errors)
            return nil, tostring(err_t), err_t
          end

          local err_t = self.errors:invalid_unique(name, errors)
          return nil, tostring(err_t), err_t
        end

        local entity_to_upsert, err, err_t = check_upsert(self, entity, options,
                                                          name, unique_value)
        if not entity_to_upsert then
          return nil, err, err_t
        end

        local row, err_t = self.strategy:upsert_by_field(name, unique_value,
                                                         entity_to_upsert, options)
        if not row then
          return nil, tostring(err_t), err_t
        end

        row, err, err_t = self:row_to_entity(row, options)
        if not row then
          return nil, err, err_t
        end

        self:post_crud_event("update", row, nil, options)

        return row
      end

      methods["delete_by_" .. name] = function(self, unique_value, options)
        validate_unique_type(unique_value, name, field)

        if options ~= nil then
          validate_options_type(options)
        end

        local ok, errors = schema:validate_field(field, unique_value)
        if not ok then
          if field_is_foreign then
            local err_t = self.errors:invalid_foreign_key(errors)
            return nil, tostring(err_t), err_t
          end

          local err_t = self.errors:invalid_unique(name, errors)
          return nil, tostring(err_t), err_t
        end

        if options ~= nil then
          ok, errors = validate_options_value(self, options)
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

        self:post_crud_event("delete", entity, nil, options)
        propagate_cascade_delete_events(cascade_entries, options)

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
    db         = db,
    schema     = schema,
    strategy   = strategy,
    errors     = errors,
    pagination = utils.shallow_copy(defaults.pagination),
    super      = super,
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
    ok, errors = validate_options_value(self, options)
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

  return self:row_to_entity(row, options)
end


function DAO:page(size, offset, options)
  if size ~= nil then
    validate_size_type(size)
  end

  if offset ~= nil then
    validate_offset_type(offset)
  end

  options = get_pagination_options(self, options)

  if size ~= nil then
    local ok, err = validate_size_value(size, options.pagination.max_page_size)
    if not ok then
      local err_t = self.errors:invalid_size(err)
      return nil, tostring(err_t), err_t
    end

  else
    size = options.pagination.page_size
  end

  local ok, errors = validate_options_value(self, options)
  if not ok then
    local err_t = self.errors:invalid_options(errors)
    return nil, tostring(err_t), err_t
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

  return entities, err, err_t, offset
end


function DAO:each(size, options)
  if size ~= nil then
    validate_size_type(size)
  end

  options = get_pagination_options(self, options)

  if size ~= nil then
    local ok, err = validate_size_value(size, options.pagination.max_page_size)
    if not ok then
      local err_t = self.errors:invalid_size(err)
      return nil, tostring(err_t), err_t
    end

  else
    size = options.pagination.page_size
  end

  local ok, errors = validate_options_value(self, options)
  if not ok then
    local err_t = self.errors:invalid_options(errors)
    return nil, tostring(err_t), err_t
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

  local entity_to_insert, err, err_t = check_insert(self, entity, options)
  if not entity_to_insert then
    return nil, err, err_t
  end

  local row, err_t = self.strategy:insert(entity_to_insert, options)
  if not row then
    return nil, tostring(err_t), err_t
  end

  row, err, err_t = self:row_to_entity(row, options)
  if not row then
    return nil, err, err_t
  end

  self:post_crud_event("create", row, nil, options)

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

  local entity_to_update, rbw_entity, err, err_t = check_update(self,
                                                                primary_key,
                                                                entity,
                                                                options)
  if not entity_to_update then
    return nil, err, err_t
  end

  local row, err_t = self.strategy:update(primary_key, entity_to_update, options)
  if not row then
    return nil, tostring(err_t), err_t
  end

  row, err, err_t = self:row_to_entity(row, options)
  if not row then
    return nil, err, err_t
  end

  self:post_crud_event("update", row, rbw_entity, options)

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

  local entity_to_upsert, err, err_t = check_upsert(self, entity, options)
  if not entity_to_upsert then
    return nil, err, err_t
  end

  local row, err_t = self.strategy:upsert(primary_key, entity_to_upsert, options)
  if not row then
    return nil, tostring(err_t), err_t
  end

  row, err, err_t = self:row_to_entity(row, options)
  if not row then
    return nil, err, err_t
  end

  self:post_crud_event("update", row, nil, options)

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
    ok, errors = validate_options_value(self, options)
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

  self:post_crud_event("delete", entity, nil, options)
  propagate_cascade_delete_events(cascade_entries, options)

  return true
end


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
    return setmetatable(rows, cjson.array_mt)
  end

  local entities = new_tab(count, 0)

  for i = 1, count do
    local entity, err, err_t = self:row_to_entity(rows[i], options)
    if not entity then
      return nil, err, err_t
    end

    entities[i] = entity
  end

  return setmetatable(entities, cjson.array_mt)
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

  local transformed_entity, err = self.schema:transform(entity, row, "select")
  if not transformed_entity then
    local err_t = self.errors:transformation_error(err)
    return nil, tostring(err_t), err_t
  end

  return transformed_entity
end


function DAO:post_crud_event(operation, entity, old_entity, options)
  if options and options.no_broadcast_crud_event then
    return
  end

  if self.events then
    local ok, err = self.events.post_local("dao:crud", operation, {
      operation  = operation,
      schema     = self.schema,
      entity     = entity,
      old_entity = old_entity,
    })
    if not ok then
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
    if value == null or value == nil then
      value = ""
    elseif field.type == "foreign" then
      -- FIXME extract foreign key, do not assume `id`
      value = value.id
    end
    values[i] = tostring(value)
    i = i + 1
  end
  for n = i, 6 do
    values[n] = ""
  end

  return concat(values, ":")
end


--[[
function DAO:load_translations(t)
  self.schema:load_translations(t)
end
--]]


return _M
