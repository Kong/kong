local arrays        = require "pgmoon.arrays"
local json          = require "pgmoon.json"
local cjson_safe    = require "cjson.safe"
local utils         = require "kong.tools.utils"
local new_tab       = require "table.new"
local clear_tab     = require "table.clear"


local kong          = kong
local ngx           = ngx
local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64
local encode_array  = arrays.encode_array
local encode_json   = json.encode_json
local setmetatable  = setmetatable
local update_time   = ngx.update_time
local get_phase     = ngx.get_phase
local tonumber      = tonumber
local concat        = table.concat
local insert        = table.insert
local assert        = assert
local ipairs        = ipairs
local pairs         = pairs
local error         = error
local upper         = string.upper
local pack          = table.pack -- luacheck: ignore
local null          = ngx.null
local type          = type
local load          = load
local find          = string.find
local now           = ngx.now
local fmt           = string.format
local rep           = string.rep
local sub           = string.sub
local log           = ngx.log


local NOTICE        = ngx.NOTICE
local LIMIT         = {}
local UNIQUE        = {}


local function noop(...)
  return ...
end


local function now_updated()
  update_time()
  return now()
end


-- @param name Query name, for debugging purposes
-- @param query A string describing an array of single-quoted strings which
-- contain parts of an SQL query including numeric placeholders like $0, $1, etc.
-- All parts of that array were processed via using string.format("%q"),
-- so that all newlines and quotes are preserved.
-- @return Produces a function which, given an array of arguments,
-- interpolates them in the right places and outputs a ready-to-use SQL query.
local function compile(name, query)
  local c = [=====[
    local v = ... or {}
    return concat { ]=====]
    .. query:gsub("$(%d+)", [[", v[%1], "]])
    .. [=====[
    }
  ]=====]
  return load(c, "=" .. name, "t", { concat = concat })
end


local function expand(name, map)
  local skip = {}
  local c = { "local row = ... or {}\n" }
  for _, field in ipairs(map) do
    local entity = field.entity
    if not skip[entity] then
      skip[entity] = true

      local exps = {}
      local keys = {}
      local nils = {}
      for _, key in ipairs(map) do
        if key.entity == entity then
          insert(exps, 'row["' .. key.from .. '"] ~= null')
          if key.to ~= "ws_id" then
            insert(keys, fmt('["%s"] = row["%s"]', key.to, key.from))
          end
          insert(nils, fmt('row["%s"] = nil', key.from))
        end
      end

      insert(c, (([[
        if $EXPS then
           row["$ENTITY"] = { $KEYS }
        else
           row["$ENTITY"] = null
        end
        $NILS
      ]]):gsub("$(%a+)", {
        ENTITY = entity,
        EXPS = concat(exps, " and "),
        KEYS = concat(keys, ", "),
        NILS = concat(nils, "; "),
      })))
    end
  end
  insert(c, "return row")

  return load(concat(c), "=" .. name, "t", { null = null })
end


local function collapse(name, map)
  local skip = {}
  local c = { [[
    local t = { ... }
    local row = {}
    for _, a in ipairs(t) do
      for k, v in pairs(a) do
        row[k] = v
      end
    end
  ]] }
  for _, field in ipairs(map) do
    local entity = field.entity
    if not skip[entity] then
      skip[entity] = true

      local keys = {}
      local nulls = {}
      for _, key in ipairs(map) do
        if key.entity == entity then
          insert(keys,  fmt('row["%s"] = row["%s"]["%s"]', key.from, entity, key.to))
          insert(nulls, fmt('row["%s"] = null', key.from))
        end
      end

      insert(c, (([[
        if row["$ENTITY"] ~= nil and row["$ENTITY"] ~= null then
          $KEYS
          row["$ENTITY"] = nil
        elseif row["$ENTITY"] == null then
          $NULLS
          row["$ENTITY"] = nil
        end
      ]]):gsub("$(%a+)", {
        ENTITY = entity,
        KEYS = concat(keys, "; "),
        NULLS = concat(nulls, "; "),
      })))
    end
  end
  insert(c, "return row")
  local env = { ipairs = ipairs, pairs = pairs, null = null }
  return load(concat(c), "=" .. name, "t", env)
end


local function escape_identifier(connector, identifier, field)
  identifier = connector:escape_identifier(identifier)

  if field and field.timestamp then
    return concat { "EXTRACT(EPOCH FROM ", identifier, " AT TIME ZONE 'UTC') AS ", identifier }
  end

  return identifier
end


local function escape_literal(connector, literal, field)
  if literal == nil or literal == null then
    return "NULL"
  end

  if field then
    if field.timestamp then
      return concat { "TO_TIMESTAMP(", connector:escape_literal(tonumber(fmt("%.3f", literal))), ") AT TIME ZONE 'UTC'" }
    end

    if field.type == "integer" then
      return fmt("%16.f", literal)
    end

    if field.type == "array" or field.type == "set" then
      if not literal[1] then
        return connector:escape_literal("{}")
      end

      local elements = field.elements

      if elements.timestamp then
        local timestamps = {}
        for i, v in ipairs(literal) do
          timestamps[i] = concat { "TO_TIMESTAMP(", connector:escape_literal(tonumber(fmt("%.3f", v))), ") AT TIME ZONE 'UTC'" }
        end
        return encode_array(timestamps)
      end

      local et = elements.type

      if et == "array" or et == "set" then
        local el = elements
        repeat
          el = el.elements
          et = el.type
        until et ~= "array" and et ~= "set"

        if et == "map" or et == "record" then
          return error("postgres strategy to escape multidimensional arrays of maps or records is not implemented")
        end

      elseif et == "map" or et == "record" or et == "json" then
        local jsons = {}
        for i, v in ipairs(literal) do
          jsons[i] = cjson_safe.encode(v)
        end
        return encode_array(jsons) .. '::JSONB[]'

      elseif et == "string" and elements.uuid then
        return encode_array(literal) .. '::UUID[]'
      end

      return encode_array(literal)

    elseif field.type == "map" or field.type == "record" or field.type == "json" then
      return encode_json(literal)
    end
  end

  return connector:escape_literal(literal)
end


local function toerror(strategy, err, primary_key, entity)
  local schema = strategy.schema
  local errors = strategy.errors

  if find(err, "violates unique constraint",   1, true) then
    log(NOTICE, err)

    if find(err, "cache_key", 1, true) then
      local keys = {}
      for _, k in ipairs(schema.cache_key) do
        local field = schema.fields[k]
        if field.type == "foreign" and entity[k] ~= null then
          keys[k] = field.schema:extract_pk_values(entity[k])
        else
          keys[k] = entity[k]
        end
      end
      return nil, errors:unique_violation(keys)
    end

    for field_name, field in schema:each_field() do
      if field.unique then
        if find(err, field_name, 1, true) then
          return nil, errors:unique_violation({
            [field_name] = entity[field_name]
          })
        end
      end
    end

    if not primary_key then
      primary_key = {}
      if entity then
        for _, key in ipairs(schema.primary_key) do
          primary_key[key] = entity[key]
        end
      end
    end
    return nil, errors:primary_key_violation(primary_key)

  elseif find(err, "violates not-null constraint", 1, true) then
    -- not-null constraint is currently only enforced on primary key
    log(NOTICE, err)
    if not primary_key then
      primary_key = {}
      if entity then
        for _, key in ipairs(schema.primary_key) do
          primary_key[key] = entity[key]
        end
      end
    end
    return nil, errors:primary_key_violation(primary_key)

  elseif find(err, "violates foreign key constraint .*_ws_id_fkey") then
    if schema.name == "workspaces" then
      local found, e = find(err, "is still referenced from table", 1, true)
      if not found then
        return error("could not parse foreign key violation error message: " .. err)
      end

      return nil, errors:foreign_key_violation_restricted(schema.name, sub(err, e + 3, -3))

    else
      local ws_id = err:match("ws_id%)=%(([^)]*)%)") or "null"
      return nil, errors:invalid_workspace(ws_id)
    end

  elseif find(err, "violates foreign key constraint", 1, true) then
    log(NOTICE, err)
    if find(err, "is not present in table", 1, true) then
      local foreign_field_name
      local foreign_schema
      for field_name, field in schema:each_field() do
        if field.type == "foreign" then
          local escaped_identifier = escape_identifier(strategy.connector,
                                                       field.schema.name)

          if find(err, escaped_identifier, 1, true) then
            foreign_field_name = field_name
            foreign_schema     = field.schema
            break
          end
        end
      end

      if not foreign_schema then
        return error("could not determine foreign schema for violated foreign key error")
      end

      local foreign_key = {}
      for _, key in ipairs(foreign_schema.primary_key) do
        if entity[foreign_field_name] then
          foreign_key[key] = entity[foreign_field_name][key]

        else
          if primary_key[key] then
            foreign_key[key] = primary_key[key]

          elseif primary_key[foreign_field_name] then
            foreign_key[key] = primary_key[foreign_field_name][key]
          end
        end
      end

      return nil, errors:foreign_key_violation_invalid_reference(foreign_key,
                                                                 foreign_field_name,
                                                                 foreign_schema.name)

    else
      local found, e = find(err, "is still referenced from table", 1, true)
      if not found then
        return error("could not parse foreign key violation error message: " .. err)
      end

      return nil, errors:foreign_key_violation_restricted(schema.name, sub(err, e + 3, -3))
    end
  end

  return nil, errors:database_error(err)
end


local function get_ttl_value(strategy, attributes, options)
  local ttl_value = options and options.ttl
  local is_update = options and options.update
  local fields = strategy.fields

  if ttl_value == 0 or not ttl_value then
    return null
  end

  if not is_update and
     attributes.created_at and
     fields.created_at and
     fields.created_at.timestamp and
     fields.created_at.auto then
    return ttl_value + attributes.created_at
  end

  if is_update and
     attributes.updated_at and
     fields.updated_at and
     fields.updated_at.timestamp and
     fields.updated_at.auto then
    return ttl_value + attributes.updated_at
  end

  return ttl_value + now_updated()
end


local function get_ws_id()
  local phase = get_phase()
  if phase ~= "init" and phase ~= "init_worker" then
    return ngx.ctx.workspace or kong.default_workspace
  end
end


local function execute(strategy, statement_name, attributes, options)
  local ws_id
  local has_ws_id = strategy.schema.workspaceable
  if has_ws_id then
    if options and options.workspace then
      if options.workspace ~= null then
        ws_id = options.workspace
      end
    else
      ws_id = get_ws_id()
    end

    if not ws_id then
      statement_name = statement_name .. "_global"
    end
  end

  local connector = strategy.connector
  local statement = strategy.statements[statement_name]
  if not attributes then
    return connector:query(statement[1], statement[2])
  end

  local fields = strategy.fields
  local argn   = statement.argn
  local argv   = statement.argv
  local argc   = statement.argc

  clear_tab(argv)

  local is_update = options and options.update
  local has_ttl   = strategy.schema.ttl

  if has_ws_id then
    assert(ws_id == nil or type(ws_id) == "string")
    argv[0] = escape_literal(connector, ws_id, "ws_id")
  end

  for i = 1, argc do
    local name = argn[i]
    local value
    if has_ttl and name == "ttl" then
      value = (options and options.ttl)
              and get_ttl_value(strategy, attributes, options)

    elseif i == argc and is_update and attributes[UNIQUE] then
      value = attributes[UNIQUE]
      if type(value) == "table" then
        value = value[name]
      end

    else
      value = attributes[name]
    end

    argv[i] = (value == nil and is_update)
              and escape_identifier(connector, name)
              or  escape_literal(connector, value, fields[name])
  end

  local sql = statement.make(argv)
  return connector:query(sql, statement.operation)
end


local function page(self, size, token, foreign_key, foreign_entity_name, options)
  if not size then
    size = self.connector:get_page_size(options)
  end

  local limit = size + 1

  local statement_name
  local attributes = {
    [LIMIT] = limit,
  }

  local suffix = token and "_next" or "_first"
  if foreign_entity_name then
    statement_name = "page_for_" .. foreign_entity_name .. suffix
    attributes[foreign_entity_name] = foreign_key

  elseif options and options.tags then
    statement_name = options.tags_cond == "or" and
                    "page_by_tags_or" .. suffix or
                    "page_by_tags_and" .. suffix
    attributes.tags = options.tags

  else
    statement_name = "page" .. suffix
  end

  if options and options.export then
    statement_name = statement_name .. "_for_export"
  end

  if token then
    local token_decoded = decode_base64(token)
    if not token_decoded then
      return nil, self.errors:invalid_offset(token, "bad base64 encoding")
    end

    token_decoded = cjson_safe.decode(token_decoded)
    if not token_decoded then
      return nil, self.errors:invalid_offset(token, "bad json encoding")
    end

    for i, field_name in ipairs(self.schema.primary_key) do
      attributes[field_name] = token_decoded[i]
    end
  end

  local res, err = execute(self, statement_name, self.collapse(attributes), options)

  if not res then
    return toerror(self, err)
  end

  local rows = new_tab(size, 0)

  for i = 1, limit do
    local row = res[i]
    if not row then
      break
    end

    if i == limit then
      row = res[size]
      local offset = {}
      for _, field_name in ipairs(self.schema.primary_key) do
        insert(offset, row[field_name])
      end

      offset = cjson_safe.encode(offset)
      offset = encode_base64(offset, true)

      return rows, nil, offset
    end

    rows[i] = self.expand(row)
  end

  return rows
end


local function make_select_for(foreign_entity_name)
  return function(self, foreign_key, size, token, options)
    return page(self, size, token, foreign_key, foreign_entity_name, options)
  end
end


local _mt   = {}


_mt.__index = _mt


function _mt:truncate(options)
  local res, err = execute(self, "truncate", nil, options)
  if not res then
    return toerror(self, err)
  end
  return true, nil
end


function _mt:insert(entity, options)
  local res, err = execute(self, "insert", self.collapse(entity), options)
  if res then
    local row = res[1]
    if row then
      return self.expand(row), nil
    end

    return nil, nil
  end

  return toerror(self, err, nil, entity)
end


function _mt:select(primary_key, options)
  local res, err = execute(self, "select", self.collapse(primary_key), options)
  if res then
    local row = res[1]
    if row then
      return self.expand(row), nil
    end

    return nil, nil
  end

  return toerror(self, err, primary_key)
end


function _mt:select_by_field(field_name, unique_value, options)
  local statement_name = "select_by_" .. field_name
  local filter = {
    [field_name] = unique_value,
  }

  local res, err = execute(self, statement_name, self.collapse(filter), options)
  if res then
    local row = res[1]
    if row then
      return self.expand(row), nil
    end

    return nil, nil
  end

  return toerror(self, err, filter)
end


local function update_options(options)
  return {
    update = true,
    ttl    = options and options.ttl,
    workspace = options and options.workspace ~= null and options.workspace,
  }
end


function _mt:update(primary_key, entity, options)
  local res, err = execute(self, "update",
                           self.collapse(primary_key, entity),
                           update_options(options))
  if res then
    local row = res[1]
    if row then
      return self.expand(row), nil
    end
    return nil, self.errors:not_found(primary_key)
  end

  return toerror(self, err, primary_key, entity)
end


function _mt:update_by_field(field_name, unique_value, entity, options)
  local filter
  if type(unique_value) == "table" then
    filter = self.collapse({ [field_name] = unique_value })
  else
    filter = unique_value
  end

  local res, err = execute(self, "update_by_" .. field_name,
                           self.collapse({ [UNIQUE] = filter }, entity),
                           update_options(options))
  if res then
    local row = res[1]
    if row then
      return self.expand(row), nil
    end
    return nil, self.errors:not_found_by_field {
      [field_name] = unique_value,
    }
  end

  return toerror(self, err, { [field_name] = unique_value }, entity)
end


function _mt:upsert(primary_key, entity, options)
  local collapsed_entity = self.collapse(entity, primary_key)
  local res, err = execute(self, "upsert", collapsed_entity, options)
  if res then
    local row = res[1]
    if row then
      return self.expand(row), nil
    end
    return nil, self.errors:not_found(primary_key)
  end

  return toerror(self, err, primary_key, entity)
end


function _mt:upsert_by_field(field_name, unique_value, entity, options)
  local collapsed_entity = self.collapse(entity, {
    [field_name] = unique_value
  })
  local res, err = execute(self, "upsert_by_" .. field_name, collapsed_entity, options)
  if res then
    local row = res[1]
    if row then
      return self.expand(row), nil
    end
    return nil, self.errors:not_found_by_field {
      [field_name] = unique_value,
    }
  end

  return toerror(self, err, { [field_name] = unique_value }, entity)
end


function _mt:delete(primary_key, options)
  local res, err = execute(self, "delete", self.collapse(primary_key), options)
  if res then
    if res.affected_rows == 0 then
      return nil, nil
    end

    return true, nil
  end

  return toerror(self, err, primary_key)
end


function _mt:delete_by_field(field_name, unique_value, options)
  local statement_name = "delete_by_" .. field_name
  local filter = {
    [field_name] = unique_value,
  }

  local res, err = execute(self, statement_name, self.collapse(filter), options)

  if res then
    if res.affected_rows == 0 then
      return nil, nil
    end

    return true, nil
  end

  return toerror(self, err, filter)
end


function _mt:page(size, token, options)
  return page(self, size, token, nil, nil, options)
end


function _mt:escape_literal(literal, field_name)
  return escape_literal(self.connector, literal, self.fields[field_name])
end


local function format_on_condition(on_condition)
  if not on_condition then
    return nil
  end
  on_condition = upper(on_condition)
  if on_condition ~= "RESTRICT" and
     on_condition ~= "CASCADE"  and
     on_condition ~= "NULL"     and
     on_condition ~= "DEFAULT"  then
     on_condition = nil
  end
  return on_condition
end


local function where_clause(where, ...)
  local inputs = pack(...)
  return function(add_ws)
    local exps = {}
    for i = 1, inputs.n do
      local exp = inputs[i]
      if exp then
        if add_ws then
          insert(exps, exp)
        else
          if not exp:match("%(\"ws_id\" = ") then
            insert(exps, exp)
          end
        end
      end
    end

    if #exps == 0 then
      return ""
    end

    return where .. concat(exps, "\n" .. rep(" ", #where - 4) .. "AND ") .. "\n"
  end
end


local function conflict_list(has_ws_id, ...)
  local inputs = pack(...)
  return function(add_ws)
    local exps = inputs
    if add_ws and has_ws_id then
      insert(exps, 1, '"ws_id"')
    end

    return concat(exps, ", ")
  end
end


-- placeholders in queries must always be constructed as a single string,
-- to avoid ending up genering code like this: `concat { "... $", "2 AND ..." }`
local function placeholder(n)
  return "$" .. n
end


local _M  = {}


function _M.new(connector, schema, errors)
  local primary_key                   = schema.primary_key
  local primary_key_fields            = {}

  for _, field_name in ipairs(primary_key) do
    primary_key_fields[field_name]    = true
  end

  local has_ttl                       = schema.ttl == true
  local has_tags                      = schema.fields.tags ~= nil
  local has_composite_cache_key       = schema.cache_key and #schema.cache_key > 1
  local has_ws_id                     = schema.workspaceable == true
  local fields                        = {}
  local fields_hash                   = {}

  local table_name                    = schema.table_name
  local table_name_escaped            = escape_identifier(connector, table_name)

  local foreign_key_list              = {}
  local foreign_keys                  = {}

  local unique_fields                 = {}


  for field_name, field in schema:each_field() do
    if field.type == "foreign" then
      local foreign_schema           = field.schema
      local foreign_key_names        = {}
      local foreign_key_escaped      = {}
      local foreign_col_names        = {}
      local is_unique_foreign        = field.unique == true

      for _, foreign_field_name in ipairs(foreign_schema.primary_key) do
        local foreign_field
        for foreign_schema_field_name, foreign_schema_field in foreign_schema:each_field() do
          if foreign_schema_field_name == foreign_field_name then
            foreign_field = foreign_schema_field
            break
          end
        end

        local name = field_name .. "_" .. foreign_field_name

        fields_hash[name] = foreign_field

        local prepared_field         = {
          referenced_table           = foreign_schema.name,
          referenced_column          = foreign_field_name,
          on_update                  = format_on_condition(field.on_update),
          on_delete                  = format_on_condition(field.on_delete),
          name                       = name,
          name_escaped               = escape_identifier(connector, name),
          name_expression            = escape_identifier(connector, name, foreign_field),
          field_name                 = field_name,
          is_used_in_primary_key     = primary_key_fields[field_name] ~= nil,
          is_part_of_composite_key   = #foreign_schema.primary_key > 1,
          is_unique                  = foreign_field.unique == true,
          is_unique_across_ws        = foreign_field.unique_across_ws == true,
          is_endpoint_key            = schema.endpoint_key == field_name,
          is_unique_foreign          = is_unique_foreign,
        }

        if prepared_field.is_used_in_primary_key then
          primary_key_fields[field_name] = prepared_field
        end

        insert(fields, prepared_field)

        insert(foreign_key_names, name)
        insert(foreign_key_escaped, prepared_field.name_escaped)
        insert(foreign_col_names, escape_identifier(connector, foreign_field_name))
        insert(foreign_key_list, {
          from   = name,
          entity = field_name,
          to     = foreign_field_name
        })
      end

      foreign_keys[field_name] = {
        names   = foreign_key_names,
        escaped = foreign_key_escaped,
      }

    else
      fields_hash[field_name]        = field

      local is_used_in_primary_key   = primary_key_fields[field_name] ~= nil
      local is_part_of_composite_key = is_used_in_primary_key and #primary_key > 1 or false

      local prepared_field       = {
        name                     = field_name,
        name_escaped             = escape_identifier(connector, field_name),
        name_expression          = escape_identifier(connector, field_name, field),
        is_used_in_primary_key   = is_used_in_primary_key,
        is_part_of_composite_key = is_part_of_composite_key,
        is_unique                = field.unique == true,
        is_unique_across_ws      = field.unique_across_ws == true,
        is_endpoint_key          = schema.endpoint_key == field_name,
      }

      if prepared_field.is_used_in_primary_key then
        primary_key_fields[field_name] = prepared_field
      end

      insert(fields, prepared_field)
    end
  end

  local primary_key_names        = {}
  local primary_key_placeholders = {}
  local insert_names             = {}
  local insert_columns           = {}
  local insert_expressions       = {}
  local select_expressions       = {}
  local update_expressions       = {}
  local update_names             = {}
  local update_placeholders      = {}
  local upsert_expressions       = {}
  local page_next_names          = {}

  for i, field in ipairs(fields) do
    local name                     = field.name
    local name_escaped             = field.name_escaped
    local name_expression          = field.name_expression
    local is_used_in_primary_key   = field.is_used_in_primary_key
    local is_part_of_composite_key = field.is_part_of_composite_key
    local is_unique                = field.is_unique
    local is_unique_foreign        = field.is_unique_foreign
    local is_endpoint_key          = field.is_endpoint_key
    local referenced_table         = field.referenced_table

    insert(insert_names,       name)
    insert(insert_columns,     name_escaped)
    insert(insert_expressions, "$" .. i)
    insert(select_expressions, name_expression)

    if not is_used_in_primary_key then
      insert(update_names,       name)
      insert(update_expressions, name_escaped .. " = $" .. #update_names)
      insert(upsert_expressions, name_escaped .. " = " .. "EXCLUDED." .. name_escaped)
    end

    if ((not is_used_in_primary_key) or is_part_of_composite_key)
       and ((referenced_table and not is_part_of_composite_key)
            or is_unique_foreign
            or is_unique
            or (is_endpoint_key and not is_unique))
    then
      -- treat endpoint_key like a unique key anyway,
      -- they are indexed (example: target.target)
      insert(unique_fields, field)
    end
  end

  local update_args_names = {}

  for _, update_name in ipairs(update_names) do
    insert(update_args_names, update_name)
  end

  local cache_key_escaped
  if has_composite_cache_key then
    cache_key_escaped = escape_identifier(connector, "cache_key")
    insert(update_names, "cache_key")
    insert(update_args_names, "cache_key")
    insert(update_expressions, cache_key_escaped .. " = $" .. #update_names)
    insert(upsert_expressions, cache_key_escaped .. " = "  .. "EXCLUDED." .. cache_key_escaped)
  end

  local ws_id_escaped
  if has_ws_id then
    ws_id_escaped = escape_identifier(connector, "ws_id")
    insert(select_expressions, ws_id_escaped)
    insert(update_names, "ws_id")
    insert(update_args_names, "ws_id")
    insert(update_expressions, ws_id_escaped .. " = $0")
    insert(upsert_expressions, ws_id_escaped .. " = "  .. "EXCLUDED." .. ws_id_escaped)
  end

  local ttl_escaped
  if has_ttl then
    ttl_escaped = escape_identifier(connector, "ttl")
    insert(update_names, "ttl")
    insert(update_args_names, "ttl")
    insert(update_expressions, ttl_escaped .. " = $" .. #update_names)
    insert(upsert_expressions, ttl_escaped .. " = "  .. "EXCLUDED." .. ttl_escaped)
  end

  local primary_key_escaped = {}
  for i, key in ipairs(primary_key) do
    local primary_key_field = primary_key_fields[key]

    insert(page_next_names,          primary_key_field.name)
    insert(primary_key_names,        primary_key_field.name)
    insert(primary_key_escaped,      primary_key_field.name_escaped)
    insert(update_args_names,        primary_key_field.name)
    insert(update_placeholders,      "$" .. #update_args_names)
    insert(primary_key_placeholders, "$" .. i)
  end

  insert(page_next_names, LIMIT)

  local pk_escaped = concat(primary_key_escaped, ", ")

  select_expressions       = concat(select_expressions, ", ")
  primary_key_placeholders = concat(primary_key_placeholders, ", ")
  update_placeholders      = concat(update_placeholders, ", ")

  if has_composite_cache_key then
    fields_hash.cache_key = { type = "string" }

    insert(insert_names, "cache_key")
    insert(insert_expressions, "$" .. #insert_names)
    insert(insert_columns, cache_key_escaped)
  end

  local ws_id_select_where
  if has_ws_id then
    fields_hash.ws_id = { type = "string", uuid = true }

    insert(insert_names, "ws_id")
    insert(insert_expressions, "$0")
    insert(insert_columns, ws_id_escaped)

    ws_id_select_where = "(" .. ws_id_escaped .. " = $0)"
  end

  local select_for_export_expressions
  local ttl_select_where
  if has_ttl then
    fields_hash.ttl = { timestamp = true }

    insert(insert_names, "ttl")
    insert(insert_expressions, "$" .. #insert_names)
    insert(insert_columns, ttl_escaped)

    select_for_export_expressions = concat {
      select_expressions, ",",
      "FLOOR(EXTRACT(EPOCH FROM (",
        ttl_escaped, " AT TIME ZONE 'UTC'",
      "))) AS ", ttl_escaped
    }

    select_expressions = concat {
      select_expressions, ",",
      "FLOOR(EXTRACT(EPOCH FROM (",
        ttl_escaped, " AT TIME ZONE 'UTC' - CURRENT_TIMESTAMP AT TIME ZONE 'UTC'",
      "))) AS ", ttl_escaped
    }

    ttl_select_where = concat {
      "(", ttl_escaped, " IS NULL OR ", ttl_escaped, " >= CURRENT_TIMESTAMP AT TIME ZONE 'UTC')"
    }
  end

  insert_expressions = concat(insert_expressions,  ", ")
  insert_columns = concat(insert_columns, ", ")

  update_expressions = concat(update_expressions, ", ")

  upsert_expressions = concat(upsert_expressions, ", ")

  local primary_key_args = {}
  local insert_args      = {}
  local update_args      = {}
  local single_args      = {}
  local page_next_args   = {}

  local self = setmetatable({
    connector    = connector,
    schema       = schema,
    errors       = errors,
    expand       = #foreign_key_list > 0 and
                   expand(table_name .. "_expand", foreign_key_list) or
                   noop,
    collapse     = collapse(table_name .. "_collapse", foreign_key_list),
    fields       = fields_hash,

    statements = {
      truncate = {
        concat {
          "TRUNCATE ", table_name_escaped, " RESTART IDENTITY CASCADE;"
        },
        "write",
      },
    }
  }, _mt)

  self.statements["truncate_global"] = self.statements["truncate"]

  local add_statement
  local add_statement_for_export
  do
    local function add(name, opts, add_ws)
      local orig_argn = opts.argn
      opts = utils.cycle_aware_deep_copy(opts)

      -- ensure LIMIT table is the same
      for i, n in ipairs(orig_argn) do
        if type(n) == "table" then
          opts.argn[i] = n
        end
      end

      for i = 1, #opts.code do
        if type(opts.code[i]) == "function" then
          opts.code[i] = opts.code[i](add_ws)
        end
        opts.code[i] = fmt("%q", opts.code[i])
      end
      opts.make = compile(table_name .. "_" .. name, concat(opts.code, ", "))
      opts.code = nil
      opts.argc = #opts.argn
      self.statements[name] = opts
    end

    add_statement = function(name, opts)
      add(name .. "_global", opts, false)
      add(name, opts, true)
    end

    add_statement_for_export = function(name, opts)
      add_statement(name, opts)
      if has_ttl then
        opts.code[2] = select_for_export_expressions
        add_statement(name .. "_for_export", opts)
      end
    end
  end

  add_statement("insert", {
    operation = "write",
    expr = insert_expressions,
    cols = insert_columns,
    argn = insert_names,
    argv = insert_args,
    code =  {
      "INSERT INTO ",  table_name_escaped, " (", insert_columns, ")\n",
      "     VALUES (", insert_expressions, ")\n",
      "  RETURNING ", select_expressions, ";",
    }
  })

  add_statement("upsert", {
    operation = "write",
    expr = upsert_expressions,
    argn = insert_names,
    argv = insert_args,
    code =  {
      "INSERT INTO ",  table_name_escaped, " (", insert_columns, ")\n",
      "     VALUES (", insert_expressions, ")\n",
      "ON CONFLICT (", pk_escaped, ") DO UPDATE\n",
      "        SET ",  upsert_expressions, "\n",
      "  RETURNING ", select_expressions, ";",
    }
  })

  add_statement("update", {
    operation = "write",
    expr = update_expressions,
    argn = update_args_names,
    argv = update_args,
    code =  {
      "   UPDATE ",  table_name_escaped, "\n",
      "      SET ",  update_expressions, "\n",
      where_clause(
      "    WHERE ", "(" .. pk_escaped .. ") = (" .. update_placeholders .. ")",
                    ttl_select_where,
                    ws_id_select_where),
      "RETURNING ", select_expressions, ";",
    }
  })

  add_statement("delete", {
    operation = "write",
    argn = primary_key_names,
    argv = primary_key_args,
    code = {
      "DELETE\n",
      "  FROM ", table_name_escaped, "\n",
      where_clause(
      " WHERE ", "(" .. pk_escaped .. ") = (" .. primary_key_placeholders .. ")",
                 ttl_select_where,
                 ws_id_select_where), ";"
    }
  })

  add_statement("select", {
    operation = "read",
    expr = select_expressions,
    argn = primary_key_names,
    argv = primary_key_args,
    code = {
      "SELECT ",  select_expressions, "\n",
      "  FROM ",  table_name_escaped, "\n",
      where_clause(
      " WHERE ", "(" .. pk_escaped .. ") = (" .. primary_key_placeholders .. ")",
                 ttl_select_where,
                 ws_id_select_where),
      " LIMIT 1;"
    }
  })

  add_statement_for_export("page_first", {
    operation = "read",
    argn = { LIMIT },
    argv = single_args,
    code = {
      "  SELECT ",  select_expressions, "\n",
      "    FROM ",  table_name_escaped, "\n",
      where_clause(
      "   WHERE ", ttl_select_where,
                   ws_id_select_where),
      "ORDER BY ",  pk_escaped, "\n",
      "   LIMIT $1;";
    }
  })

  add_statement_for_export("page_next", {
    operation = "read",
    argn = page_next_names,
    argv = page_next_args,
    code = {
      "  SELECT ",  select_expressions, "\n",
      "    FROM ",  table_name_escaped, "\n",
      where_clause(
      "   WHERE ", "(" .. pk_escaped .. ") > (" .. primary_key_placeholders .. ")",
                   ttl_select_where,
                   ws_id_select_where),
      "ORDER BY ",  pk_escaped, "\n",
      "   LIMIT " .. placeholder(#page_next_names), ";"
    }
  })

  if #foreign_key_list > 0 then
    for foreign_entity_name, foreign_key in pairs(foreign_keys) do
      local fk_names   = foreign_key.names
      local fk_escaped = foreign_key.escaped

      local fk_placeholders = {}
      local pk_placeholders = {}

      local foreign_key_names = concat(fk_escaped, ", ")

      local argv_first = {}
      local argn_first = {}
      local argv_next  = {}
      local argn_next  = {}

      for i, fk_name in ipairs(fk_names) do
        insert(argn_first, fk_name)
        insert(argn_next, fk_name)
        insert(fk_placeholders, placeholder(i))
      end

      for i, primary_key_name in ipairs(primary_key_names) do
        insert(argn_next, primary_key_name)
        insert(pk_placeholders, placeholder(i + #fk_names))
      end

      insert(argn_first, LIMIT)
      insert(argn_next, LIMIT)

      fk_placeholders = concat(fk_placeholders, ", ")
      pk_placeholders = concat(pk_placeholders, ", ")

      local statement_name = "page_for_" .. foreign_entity_name

      add_statement_for_export(statement_name .. "_first", {
        operation = "read",
        argn = argn_first,
        argv = argv_first,
        code = {
          "  SELECT ",  select_expressions, "\n",
          "    FROM ",  table_name_escaped, "\n",
          where_clause(
          "   WHERE ", "(" .. foreign_key_names .. ") = (" .. fk_placeholders .. ")",
                       ttl_select_where,
                       ws_id_select_where),
          "ORDER BY ", pk_escaped, "\n",
          "   LIMIT ", placeholder(#argn_first), ";";
        }
      })

      add_statement_for_export(statement_name .. "_next", {
        operation = "read",
        argn = argn_next,
        argv = argv_next,
        code = {
          "  SELECT ",  select_expressions, "\n",
          "    FROM ",  table_name_escaped, "\n",
          where_clause(
          "   WHERE ", "(" .. foreign_key_names .. ") = (" .. fk_placeholders .. ")",
                       "(" .. pk_escaped .. ") > (" .. pk_placeholders .. ")",
                       ttl_select_where,
                       ws_id_select_where),
          "ORDER BY ", pk_escaped, "\n",
          "   LIMIT ", placeholder(#argn_next), ";"
        }
      })

      self[statement_name] = make_select_for(foreign_entity_name)
    end
  end

  if has_tags then
    local pk_placeholders = {}

    local argn_first = { "tags", LIMIT }
    local argn_next  = { "tags" }

    for i, primary_key_name in ipairs(primary_key_names) do
      insert(argn_next, primary_key_name)
      pk_placeholders[i] = placeholder(i + 1)
    end
    insert(argn_next, LIMIT)

    for cond, op in pairs({["_and"] = "@>", ["_or"] = "&&"}) do

      add_statement_for_export("page_by_tags" .. cond .. "_first", {
        operation = "read",
        argn = argn_first,
        argv = {},
        code = {
          "  SELECT ",  select_expressions, "\n",
          "    FROM ",  table_name_escaped, "\n",
          where_clause(
          "   WHERE ", "tags " .. op .. " $1",
                       ttl_select_where,
                       ws_id_select_where),
          "ORDER BY ",  pk_escaped, "\n",
          "   LIMIT $2;";
        },
      })

      add_statement_for_export("page_by_tags" .. cond .. "_next", {
        operation = "read",
        argn = argn_next,
        argv = {},
        code = {
          "  SELECT ",  select_expressions, "\n",
          "    FROM ",  table_name_escaped, "\n",
          where_clause(
          "   WHERE ", "tags " .. op .. " $1",
                       "(" .. pk_escaped .. ") > (" .. concat(pk_placeholders, ", ") .. ")",
                       ttl_select_where,
                       ws_id_select_where),
          "ORDER BY ", pk_escaped, "\n",
          "   LIMIT ", placeholder(#argn_next), ";"
        }
      })
    end
  end

  if has_composite_cache_key then
    insert(unique_fields, {
      name = "cache_key",
      name_escaped = escape_identifier(connector, "cache_key"),
    })
  end

  if #unique_fields > 0 then
    local update_by_args = {}

    for _, unique_field in ipairs(unique_fields) do
      local field_name     = unique_field.field_name or unique_field.name
      local unique_name    = unique_field.name
      local unique_escaped = unique_field.name_escaped
      local single_names   = { unique_name }

      add_statement("select_by_" .. field_name, {
        operation = "read",
        argn = single_names,
        argv = single_args,
        code = {
          "SELECT ",  select_expressions, "\n",
          "  FROM ",  table_name_escaped, "\n",
          where_clause(
          " WHERE ",  unique_escaped .. " = $1",
                      ttl_select_where,
                      ws_id_select_where),
          " LIMIT 1;"
        },
      })

      local update_by_args_names = {}
      for _, update_name in ipairs(update_names) do
        insert(update_by_args_names, update_name)
      end

      insert(update_by_args_names, unique_name)

      add_statement("update_by_" .. field_name, {
        operation = "write",
        argn = update_by_args_names,
        argv = update_by_args,
        code = {
          "   UPDATE ", table_name_escaped, "\n",
          "      SET ", update_expressions, "\n",
          where_clause(
          "    WHERE ", unique_escaped .. " = $" .. #update_names + 1,
                        ttl_select_where,
                        ws_id_select_where),
          "RETURNING ", select_expressions, ";",
        }
      })

      local conflict_key = unique_escaped
      if has_composite_cache_key and not unique_field.is_endpoint_key then
        conflict_key = escape_identifier(connector, "cache_key")
      end

      local use_ws_id = has_ws_id and not unique_field.is_unique_across_ws

      add_statement("upsert_by_" .. field_name, {
        operation = "write",
        argn = insert_names,
        argv = insert_args,
        code = {
          "INSERT INTO ",  table_name_escaped, " (", insert_columns, ")\n",
          "     VALUES (", insert_expressions, ")\n",
          "ON CONFLICT (", conflict_list(use_ws_id, conflict_key), ") DO UPDATE\n",
          "        SET ",  upsert_expressions, "\n",
          "  RETURNING ",  select_expressions, ";",
        }
      })

      add_statement("delete_by_" .. field_name, {
        operation = "write",
        argn = single_names,
        argv = single_args,
        code = {
          "DELETE\n",
          "  FROM ",  table_name_escaped, "\n",
          where_clause(
          " WHERE ",  unique_escaped .. " = $1",
                      ttl_select_where,
                      ws_id_select_where), ";"
        }
      })
    end
  end

  return self
end


return _M
