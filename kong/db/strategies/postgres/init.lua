local arrays        = require "pgmoon.arrays"
local json          = require "pgmoon.json"
local cjson         = require "cjson"
local cjson_safe    = require "cjson.safe"


local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64
local encode_array  = arrays.encode_array
local encode_json   = json.encode_json
local setmetatable  = setmetatable
local update_time   = ngx.update_time
local tonumber      = tonumber
local concat        = table.concat
local insert        = table.insert
local ipairs        = ipairs
local pairs         = pairs
local error         = error
local upper         = string.upper
local null          = ngx.null
local type          = type
local load          = load
local find          = string.find
local now           = ngx.now
local fmt           = string.format
local rep           = string.rep
local sub           = string.sub
local max           = math.max
local log           = ngx.log


local NOTICE        = ngx.NOTICE
local LIMIT         = {}
local UNIQUE        = {}


local new_tab
local clear_tab


do
  local pcall = pcall
  local ok

  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function () return {} end
  end

  ok, clear_tab = pcall(require, "table.clear")
  if not ok then
    clear_tab = function (tab)
      for k, _ in pairs(tab) do
        tab[k] = nil
      end
    end
  end
end


local function noop(...)
  return ...
end


local function now_updated()
  update_time()
  return now()
end


local function compile(name, query)
  local i, n, p, s, e = 1, 2, 0, find(query, "$1", 1, true)
  local c = {
    "local _ = ... or {}\n",
    "return concat{\n",
  }
  while s do
    if i < s then
      c[n+1] = "[=[\n"
      c[n+2] = sub(query, i, s - 1)
      c[n+3] = "]=], "
      n=n+3
    end
    p=p+1
    c[n+1] = "_["
    c[n+2] = p
    c[n+3] = "], "
    n=n+3
    i = e + 1
    s, e = find(query, "$" .. p + 1, i, true)
  end
  s = sub(query, i)
  if s and s ~= "" then
    c[n+1] = "[=[\n"
    c[n+2] = s
    c[n+3] = "]=]"
    n=n+3
  end
  c[n+1] = " }"
  return load(concat(c), "=" .. name, "t", { concat = concat })
end


local function expand(name, map)
  local h = {}
  local n = 1
  local c = { "local _ = ... or {}\n" }
  for _, field in ipairs(map) do
    local entity = field.entity
    if not h[entity] then
      h[entity] = true
      c[n+1] = "if "
      n=n+1
      for _, key in ipairs(map) do
        if entity == key.entity then
          c[n+1] = '_["'
          c[n+2] = field.from
          c[n+3] = '"] ~= null'
          c[n+4] = " and "
          n=n+4
        end
      end
      c[n] = " then\n"
      c[n+1] = '  \n  _["'
      c[n+2] = entity
      c[n+3] = '"] = {\n'
      n=n+3
      for _, key in ipairs(map) do
        if entity == key.entity then
          c[n+1] = '    ["'
          c[n+2] = field.to
          c[n+3] = '"] = '
          c[n+4] = '_["'
          c[n+5] = field.from
          c[n+6] = '"],\n'
          n=n+6
        end
      end
      c[n+1] = "  }\n\n"
      c[n+2] = "else\n"
      c[n+3] = '  _["'
      c[n+4] = field.entity
      c[n+5] = '"] = null\n'
      c[n+6] = "end\n"
      c[n+7] = '_["'
      c[n+8] = field.from
      c[n+9] = '"] = nil\n'
      n=n+9
    end
  end
  c[n+1] = "return _"

  return load(concat(c), "=" .. name, "t", { null = null })
end


local function collapse(name, map)
  local h = {}
  local n = 7
  local c = {
    "local t = { ... }\n",
    "local r = {}\n",
    "for _, a in ipairs(t) do\n",
    "  for k, v in pairs(a) do\n",
    "    r[k] = v\n",
    "  end\n",
    "end\n",
  }
  for _, field in ipairs(map) do
    local entity = field.entity
    if not h[entity] then
      h[entity] = true
      c[n+1] = 'if r["'
      c[n+2] = entity
      c[n+3] = '"] ~= nil and '
      c[n+4] = 'r["'
      c[n+5] = entity
      c[n+6] = '"] ~= null then\n'
      n=n+6
      for _, key in ipairs(map) do
        if entity == key.entity then
          c[n+1] = '  r["'
          c[n+2] = field.from
          c[n+3] = '"] = '
          c[n+4] = 'r["'
          c[n+5] = entity
          c[n+6] = '"]["'
          c[n+7] = field.to
          c[n+8] = '"]\n'
          n=n+8
        end
      end
      c[n+1] = '  r["'
      c[n+2] = entity
      c[n+3] = '"] = nil\n\n'
      c[n+4] = 'elseif r["'
      c[n+5] = entity
      c[n+6] = '"] == null then\n'
      n=n+6
      for _, key in ipairs(map) do
        if entity == key.entity then
          c[n+1] = '  r["'
          c[n+2] = field.from
          c[n+3] = '"] = null\n'
          n=n+3
        end
      end
      c[n+1] = '  r["'
      c[n+2] = entity
      c[n+3] = '"] = nil\n'
      c[n+4] = "end\n"
      n=n+4
    end
  end
  c[n+1] = "return r"
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

      elseif et == "map" or et == "record" then
        local jsons = {}
        for i, v in ipairs(literal) do
          jsons[i] = cjson.encode(v)
        end
        return encode_array(jsons) .. '::JSONB[]'
      end

      return encode_array(literal)

    elseif field.type == "map" or field.type == "record" then
      return encode_json(literal)
    end
  end

  return connector:escape_literal(literal)
end


local function field_type_to_postgres_type(field)
  if field.timestamp then
    return "TIMESTAMP WITH TIME ZONE"

  elseif field.uuid then
    return "UUID"
  end

  local t = field.type

  if t == "string" then
    return "TEXT"

  elseif t == "boolean" then
    return "BOOLEAN"

  elseif t == "integer" then
    return "BIGINT"

  elseif t == "number" then
    return "DOUBLE PRECISION"

  elseif t == "array" or t == "set" then
    local elements = field.elements

    if elements.timestamp then
      return "TIMESTAMP[] WITH TIME ZONE", 1

    elseif field.uuid then
      return "UUID[]", 1
    end

    local et = elements.type

    if et == "string" then
      return "TEXT[]", 1

    elseif et == "boolean" then
      return "BOOLEAN[]", 1

    elseif et == "integer" then
      return "BIGINT[]", 1

    elseif et == "number" then
      return "DOUBLE PRECISION[]", 1

    elseif et == "array" or et == "set" then
      local dm = 1
      local el = elements
      repeat
        dm = dm + 1
        el = el.elements
        et = el.type
      until et ~= "array" and et ~= "set"

      local brackets = rep("[]", dm)

      if el.timestamp then
        return "TIMESTAMP" .. brackets .. " WITH TIME ZONE", dm

      elseif field.uuid then
        return "UUID" .. brackets, dm
      end

      if et == "string" then
        return "TEXT" .. brackets, dm

      elseif et == "boolean" then
        return "BOOLEAN" .. brackets, dm

      elseif et == "integer" then
        return "BIGINT" .. brackets, dm

      elseif et == "number" then
        return "DOUBLE PRECISION" .. brackets, dm

      elseif et == "map" or et == "record" then
        return "JSONB" .. brackets, dm

      else
        return "UNKNOWN" .. brackets, dm
      end

    elseif et == "map" or et == "record" then
      return "JSONB[]", 1

    else
      return "UNKNOWN[]", 1
    end

  elseif t == "map" or t == "record" then
    return "JSONB"

  else
    return "UNKNOWN"
  end
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


local function execute(strategy, statement_name, attributes, options)
  local connector = strategy.connector
  local statement = strategy.statements[statement_name]
  if not attributes then
    return connector:query(statement)
  end

  local fields = strategy.fields
  local argn   = statement.argn
  local argv   = statement.argv
  local argc   = statement.argc

  clear_tab(argv)

  local is_update = options and options.update
  local has_ttl = strategy.schema.ttl
  local ttl_value

  if has_ttl then
    ttl_value = options and options.ttl
    if ttl_value then
      if ttl_value == 0 then
        ttl_value = escape_literal(connector, null, fields.ttl)

      elseif not is_update and
             attributes.created_at and
             fields.created_at and
             fields.created_at.timestamp and
             fields.created_at.auto then
        ttl_value = escape_literal(connector, ttl_value + attributes.created_at, fields.ttl)

      elseif is_update and
             attributes.updated_at and
             fields.updated_at and
             fields.updated_at.timestamp and
             fields.updated_at.auto then
        ttl_value = escape_literal(connector, ttl_value + attributes.updated_at, fields.ttl)

      else
        ttl_value = escape_literal(connector, ttl_value + now_updated(), fields.ttl)
      end

    else
      if is_update then
        ttl_value = escape_identifier(connector, "ttl")
      else
        ttl_value = escape_literal(connector, null, fields.ttl)
      end
    end
  end

  for i = 1, argc do
    local name  = argn[i]
    local value
    if has_ttl and name == "ttl" then
      argv[i] = ttl_value

    else
      if i == argc and is_update and attributes[UNIQUE] then
        value = attributes[UNIQUE]
        if type(value) == "table" then
          value = value[name]
        end

      else
        value = attributes[name]
      end

      if value == nil and is_update then
        argv[i] = escape_identifier(connector, name)
      else
        argv[i] = escape_literal(connector, value, fields[name])
      end
    end
  end

  local sql = statement.make(argv)
  return connector:query(sql)
end


local function page(self, size, token, foreign_key, foreign_entity_name, options)
  if not size then
    size = self.connector:get_page_size(options)
  end

  local limit = size + 1

  local statement_name
  local attributes

  if token then
    if foreign_entity_name then
      statement_name = concat({ "page_for", foreign_entity_name, "next" }, "_")
      attributes     = {
        [foreign_entity_name] = foreign_key,
        [LIMIT]               = limit,
      }

    elseif options and options.tags then
      statement_name = options.tags_cond == "or" and
                      "page_by_tags_or_next" or
                      "page_by_tags_and_next"
      attributes     = {
        tags    = options.tags,
        [LIMIT] = limit,
      }
    else
      statement_name = "page_next"
      attributes     = {
        [LIMIT] = limit,
      }
    end

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

  else
    if foreign_entity_name then
      statement_name = concat({ "page_for", foreign_entity_name, "first" }, "_")
      attributes     = {
        [foreign_entity_name] = foreign_key,
        [LIMIT]               = limit,
      }
    elseif options and options.tags then
      statement_name = options.tags_cond == "or" and
                      "page_by_tags_or_first" or
                      "page_by_tags_and_first"
      attributes     = {
        tags    = options.tags,
        [LIMIT] = limit,
      }
    else
      statement_name = "page_first"
      attributes     = {
        [LIMIT] = limit,
      }
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
      for i, field_name in ipairs(self.schema.primary_key) do
        offset[i] = row[field_name]
      end

      offset = cjson.encode(offset)
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


function _mt:create(options)
  local res, err = execute(self, "create", nil, options)
  if not res then
    return toerror(self, err)
  end
  return true, nil
end


function _mt:truncate(options)
  local res, err = execute(self, "truncate", nil, options)
  if not res then
    return toerror(self, err)
  end
  return true, nil
end


function _mt:drop(options)
  local res, err = execute(self, "drop", nil, options)
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


function _mt:update(primary_key, entity, options)
  local res, err = execute(self, "update", self.collapse(primary_key, entity), {
    update = true,
    ttl    = options and options.ttl,
  })
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

  local res, err = execute(self, "update_by_" .. field_name, self.collapse({ [UNIQUE] = filter }, entity), {
    update = true,
    ttl    = options and options.ttl,
  })
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


function _mt:count(options)
  local res, err = execute(self, "count", nil, options)
  if res then
    local row = res[1]
    if row then
      return row.count, nil

    else
      -- count should always return results unless there is an error
      return toerror(self, "unexpected")
    end
  end

  return toerror(self, err)
end


function _mt:page(size, token, options)
  return page(self, size, token, nil, nil, options)
end


function _mt:escape_literal(literal, field_name)
  return escape_literal(self.connector, literal, self.fields[field_name])
end


local _M  = {}


function _M.new(connector, schema, errors)
  local primary_key                   = schema.primary_key
  local primary_key_fields            = {}
  local primary_key_count             = 0

  for i, field_name in ipairs(primary_key) do
    primary_key_fields[field_name]    = true
    primary_key_count = i
  end

  local ttl                           = schema.ttl == true
  local tags                          = schema.fields.tags ~= nil
  local composite_cache_key           = schema.cache_key and #schema.cache_key > 1
  local max_name_length               = schema.cache_key and 11 or (ttl and 3  or 1)
  local max_type_length               = ttl and 24 or 1
  local fields                        = {}
  local fields_count                  = 0
  local fields_hash                   = {}

  local table_name                    = schema.name
  local table_name_escaped            = escape_identifier(connector, table_name)

  local foreign_key_constraints       = {}
  local foreign_key_constrainst_count = 0
  local foreign_key_indexes_escaped   = {}
  local foreign_key_indexes_count     = 0
  local foreign_key_indexes           = {}
  local foreign_key_count             = 0
  local foreign_key_list              = {}
  local foreign_keys                  = {}

  local unique_fields_count           = 0
  local unique_fields                 = {}


  for field_name, field in schema:each_field() do
    if field.type == "foreign" then
      local foreign_schema           = field.schema
      local foreign_key_names        = {}
      local foreign_key_escaped      = {}
      local foreign_col_names        = {}
      local foreign_pk_count         = #foreign_schema.primary_key
      local is_part_of_composite_key = foreign_pk_count > 1
      local is_unique_foreign        = field.unique == true

      local on_delete = field.on_delete
      if on_delete then
        on_delete = upper(on_delete)
        if on_delete ~= "RESTRICT" and
           on_delete ~= "CASCADE"  and
           on_delete ~= "NULL"     and
           on_delete ~= "DEFAULT"  then
           on_delete = nil
        end
      end

      local on_update = field.on_update
      if on_update then
        on_update = upper(on_update)
        if on_update ~= "RESTRICT" and
           on_update ~= "CASCADE"  and
           on_update ~= "NULL"     and
           on_update ~= "DEFAULT"  then
           on_update = nil
        end
      end

      for i, foreign_field_name in ipairs(foreign_schema.primary_key) do
        local foreign_field
        for foreign_schema_field_name, foreign_schema_field in foreign_schema:each_field() do
          if foreign_schema_field_name == foreign_field_name then
            foreign_field = foreign_schema_field
            break
          end
        end

        local name = concat({ field_name, foreign_field_name }, "_")

        fields_hash[name] = foreign_field

        local name_escaped           = escape_identifier(connector, name)
        local name_expression        = escape_identifier(connector, name, foreign_field)
        local type_postgres          = field_type_to_postgres_type(foreign_field)
        local is_used_in_primary_key = primary_key_fields[field_name] ~= nil
        local is_unique              = foreign_field.unique == true
        local is_endpoint_key        = schema.endpoint_key == field_name

        max_name_length              = max(max_name_length, #name_escaped)
        max_type_length              = max(max_type_length, #type_postgres)

        local prepared_field         = {
          referenced_table           = foreign_schema.name,
          referenced_column          = foreign_field_name,
          on_update                  = on_update,
          on_delete                  = on_delete,
          name                       = name,
          name_escaped               = name_escaped,
          name_expression            = name_expression,
          field_name                 = field_name,
          type_postgres              = type_postgres,
          is_used_in_primary_key     = is_used_in_primary_key,
          is_part_of_composite_key   = is_part_of_composite_key,
          is_unique                  = is_unique,
          is_endpoint_key            = is_endpoint_key,
          is_unique_foreign          = is_unique_foreign,
        }

        if prepared_field.is_used_in_primary_key then
          primary_key_fields[field_name] = prepared_field
        end

        fields_count           = fields_count + 1
        fields[fields_count]   = prepared_field

        foreign_key_names[i]   = name
        foreign_key_escaped[i] = name_escaped
        foreign_col_names[i]   = escape_identifier(connector, foreign_field_name)
        insert(foreign_key_list, {
          from   = name,
          entity = field_name,
          to     = foreign_field_name
        })
      end

      foreign_keys[field_name] = {
        names   = foreign_key_names,
        escaped = foreign_key_escaped,
        count   = foreign_pk_count,
      }

      foreign_key_count = foreign_key_count + 1

      if not is_unique_foreign then
        local foreign_key_index_name       = concat({ table_name, field_name }, "_fkey_")
        local foreign_key_index_identifier = escape_identifier(connector, foreign_key_index_name)

        foreign_key_indexes_count = foreign_key_indexes_count + 1
        foreign_key_indexes_escaped[foreign_key_indexes_count] = foreign_key_index_identifier
        foreign_key_indexes[foreign_key_indexes_count] = concat {
          "CREATE INDEX IF NOT EXISTS ", foreign_key_index_identifier, " ON ", table_name_escaped, " (", concat(foreign_key_escaped, ", "), ");",
        }
      end

      if is_part_of_composite_key then
        foreign_key_constrainst_count = foreign_key_constrainst_count + 1
        if on_delete and on_update then
          foreign_key_constraints[foreign_key_constrainst_count] = concat {
            "FOREIGN KEY (", concat(foreign_key_escaped, ", "), ")\n",
            "   REFERENCES ",  escape_identifier(connector, foreign_schema.name), " (", concat(foreign_col_names, ", "), ")\n",
            "    ON DELETE ",  on_delete, "\n",
            "    ON UPDATE ",  on_update,
          }

        elseif on_delete then
          foreign_key_constraints[foreign_key_constrainst_count] = concat {
            "FOREIGN KEY (", concat(foreign_key_escaped, ", "), ")\n",
            "   REFERENCES ",  escape_identifier(connector, foreign_schema.name), " (", concat(foreign_col_names, ", "), ")\n",
            "    ON DELETE ",  on_delete,
          }

        elseif on_update then
          foreign_key_constraints[foreign_key_constrainst_count] = concat {
            "FOREIGN KEY (", concat(foreign_key_escaped, ", "), ")\n",
            "   REFERENCES ",  escape_identifier(connector, foreign_schema.name), " (", concat(foreign_col_names, ", "), ")\n",
            "    ON UPDATE ",  on_update,
          }

        else
          foreign_key_constraints[foreign_key_constrainst_count] = concat {
            "FOREIGN KEY (", concat(foreign_key_escaped, ", "), ")\n",
            "   REFERENCES ",  escape_identifier(connector, foreign_schema.name), " (", concat(foreign_col_names, ", "), ")",
          }
        end

        if is_unique_foreign then
          foreign_key_constraints[foreign_key_constrainst_count] = concat {
            foreign_key_constraints[foreign_key_constrainst_count], ",\n",
            "       UNIQUE (", concat(foreign_key_escaped, ", "), ")"
          }
        end
      end

    else
      fields_hash[field_name]        = field

      local name_escaped             = escape_identifier(connector, field_name)
      local name_expression          = escape_identifier(connector, field_name, field)
      local type_postgres            = field_type_to_postgres_type(field)
      local is_used_in_primary_key   = primary_key_fields[field_name] ~= nil
      local is_part_of_composite_key = is_used_in_primary_key and primary_key_count > 1 or false
      local is_unique                = field.unique == true
      local is_endpoint_key          = schema.endpoint_key == field_name

      max_name_length = max(max_name_length, #name_escaped)
      max_type_length = max(max_type_length, #type_postgres)

      local prepared_field       = {
        name                     = field_name,
        name_escaped             = name_escaped,
        name_expression          = name_expression,
        type_postgres            = type_postgres,
        is_used_in_primary_key   = is_used_in_primary_key,
        is_part_of_composite_key = is_part_of_composite_key,
        is_unique                = is_unique,
        is_endpoint_key          = is_endpoint_key,
      }

      if prepared_field.is_used_in_primary_key then
        primary_key_fields[field_name] = prepared_field
      end

      fields_count         = fields_count + 1
      fields[fields_count] = prepared_field
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
  local update_fields_count      = 0
  local upsert_expressions       = {}
  local create_expressions       = {}
  local page_next_names          = {}
  local page_next_count          = primary_key_count + 1

  for i = 1, fields_count do
    local name                     = fields[i].name
    local name_escaped             = fields[i].name_escaped
    local name_expression          = fields[i].name_expression
    local type_postgres            = fields[i].type_postgres
    local is_used_in_primary_key   = fields[i].is_used_in_primary_key
    local is_part_of_composite_key = fields[i].is_part_of_composite_key
    local is_unique                = fields[i].is_unique
    local is_unique_foreign        = fields[i].is_unique_foreign
    local is_endpoint_key          = fields[i].is_endpoint_key
    local referenced_table         = fields[i].referenced_table
    local referenced_column        = fields[i].referenced_column
    local on_delete                = fields[i].on_delete
    local on_update                = fields[i].on_update

    insert_names[i]       = name
    insert_columns[i]     = name_escaped
    insert_expressions[i] = "$" .. i
    select_expressions[i] = name_expression

    if not is_used_in_primary_key then
      update_fields_count = update_fields_count + 1
      update_names[update_fields_count]       = name
      update_expressions[update_fields_count] = name_escaped .. " = $" .. update_fields_count
      upsert_expressions[update_fields_count] = name_escaped .. " = "   .. "EXCLUDED." .. name_escaped
    end

    local create_expression = {}

    create_expression[1] = name_escaped
    create_expression[2] = rep(" ", max_name_length - #name_escaped + 2)

    create_expression[3] = type_postgres

    if is_used_in_primary_key and not is_part_of_composite_key then
      create_expression[4] = rep(" ", max_type_length - #type_postgres + (#type_postgres < max_name_length and 3 or 2))
      create_expression[5] = "PRIMARY KEY"

      if referenced_table then
        if is_unique then
          create_expression[6]  = "  UNIQUE  REFERENCES "
        else
          create_expression[6]  = "  REFERENCES "
        end
        create_expression[7]  = escape_identifier(connector, referenced_table)
        create_expression[8]  = " ("
        create_expression[9]  = escape_identifier(connector, referenced_column)
        create_expression[10] = ")"

        if on_delete and on_update then
          create_expression[11] = " ON DELETE "
          create_expression[12] = on_delete
          create_expression[13] = " ON UPDATE "
          create_expression[14] = on_update

        elseif on_delete then
          create_expression[11] = " ON DELETE "
          create_expression[12] = on_delete

        elseif on_update then
          create_expression[11] = " ON UPDATE "
          create_expression[12] = on_update
        end
      end

    elseif referenced_table and not is_part_of_composite_key then
      create_expression[4] = rep(" ", max_type_length - #type_postgres + (#type_postgres < max_name_length and 3 or 2))
      if is_unique then
        create_expression[5] = "UNIQUE  REFERENCES "
      else
        create_expression[5] = "REFERENCES "
      end
      create_expression[6] = escape_identifier(connector, referenced_table)
      create_expression[7] = " ("
      create_expression[8] = escape_identifier(connector, referenced_column)
      create_expression[9] = ")"

      if on_delete and on_update then
        create_expression[10] = " ON DELETE "
        create_expression[11] = on_delete
        create_expression[12] = " ON UPDATE "
        create_expression[13] = on_update

      elseif on_delete then
        create_expression[10] = " ON DELETE "
        create_expression[11] = on_delete

      elseif on_update then
        create_expression[10] = " ON UPDATE "
        create_expression[11] = on_update
      end

      if is_unique_foreign then
        unique_fields_count = unique_fields_count + 1
        unique_fields[unique_fields_count] = fields[i]
      end

    elseif is_unique then
      if not is_used_in_primary_key and not referenced_table then
        create_expression[4] = rep(" ", max_type_length - #type_postgres + (#type_postgres < max_name_length and 3 or 2))
        create_expression[5] = "UNIQUE"
      end

      unique_fields_count = unique_fields_count + 1
      unique_fields[unique_fields_count] = fields[i]

    elseif is_endpoint_key and not is_unique then
      -- treat it like a unique key anyway - they are indexed (example: target.target)
      unique_fields_count = unique_fields_count + 1
      unique_fields[unique_fields_count] = fields[i]
    end

    create_expressions[i] = concat(create_expression)
  end

  local update_args_names = {}

  for i = 1, update_fields_count do
    update_args_names[i] = update_names[i]
  end

  local create_count = fields_count

  local cache_key_escaped
  local cache_key_index
  if composite_cache_key then
    cache_key_escaped = escape_identifier(connector, "cache_key")
    cache_key_index = escape_identifier(connector, table_name .. "_" .. "cache_key_idx")
    update_fields_count = update_fields_count + 1
    update_names[update_fields_count] = "cache_key"
    update_args_names[update_fields_count] = "cache_key"
    update_expressions[update_fields_count] = cache_key_escaped .. " = $" .. update_fields_count
    upsert_expressions[update_fields_count] = cache_key_escaped .. " = "  .. "EXCLUDED." .. cache_key_escaped

    local create_expression = {
      cache_key_escaped,
      rep(" ", max_name_length - #cache_key_escaped + 2),
      field_type_to_postgres_type({ type = "string" }),
    }

    create_count = create_count + 1
    create_expressions[create_count] = concat(create_expression)
  end

  local ttl_escaped
  local ttl_index
  if ttl then
    ttl_escaped = escape_identifier(connector, "ttl")
    ttl_index = escape_identifier(connector, table_name .. "_" .. "ttl_idx")
    update_fields_count = update_fields_count + 1
    update_names[update_fields_count] = "ttl"
    update_args_names[update_fields_count] = "ttl"
    update_expressions[update_fields_count] = ttl_escaped .. " = $" .. update_fields_count
    upsert_expressions[update_fields_count] = ttl_escaped .. " = "  .. "EXCLUDED." .. ttl_escaped

    local create_expression = {
      ttl_escaped,
      rep(" ", max_name_length - #ttl_escaped + 2),
      field_type_to_postgres_type({ timestamp = true }),
    }

    create_count = create_count + 1
    create_expressions[create_count] = concat(create_expression)
  end

  local update_args_count = update_fields_count
  local primary_key_escaped = {}
  for i = 1, primary_key_count do
    local primary_key_field              = primary_key_fields[primary_key[i]]
    primary_key_names[i]                 = primary_key_field.name
    primary_key_escaped[i]               = primary_key_field.name_escaped
    update_args_count                    = update_args_count + 1
    update_args_names[update_args_count] = primary_key_field.name
    update_placeholders[i]               = "$" .. update_args_count
    primary_key_placeholders[i]          = "$" .. i
    page_next_names[i]                   = primary_key[i]
  end

  page_next_names[page_next_count] = LIMIT

  local pk_escaped = concat(primary_key_escaped, ", ")
  if primary_key_count > 1 then
    create_count = create_count + 1
    create_expressions[create_count] = concat{
      "PRIMARY KEY (",  pk_escaped, ")"
    }
  end

  for i = 1, foreign_key_constrainst_count do
    create_count = create_count + 1
    create_expressions[create_count] = foreign_key_constraints[i]
  end

  select_expressions       = concat(select_expressions,  ", ")
  primary_key_placeholders = concat(primary_key_placeholders, ", ")
  update_placeholders      = concat(update_placeholders, ", ")

  local create_statement
  local insert_count
  local insert_statement
  local upsert_statement
  local select_statement
  local page_first_statement
  local page_next_statement
  local update_statement
  local delete_statement
  local count_statement
  local drop_statement

  if composite_cache_key then
    fields_hash.cache_key = { type = "string" }

    insert_count = fields_count + 1
    insert_names[insert_count] = "cache_key"
    insert_expressions[insert_count] = "$" .. insert_count
    insert_columns[insert_count] = cache_key_escaped
    fields_count = fields_count + 1
  end

  if ttl then
    fields_hash.ttl = { timestamp = true }

    insert_count = fields_count + 1
    insert_names[insert_count] = "ttl"
    insert_expressions[insert_count] = "$" .. insert_count
    insert_columns[insert_count] = ttl_escaped

    insert_expressions = concat(insert_expressions,  ", ")
    insert_columns = concat(insert_columns, ", ")

    update_expressions = concat(update_expressions, ", ")

    upsert_expressions = concat(upsert_expressions, ", ")

    select_expressions = concat {
      select_expressions, ",",
      "FLOOR(EXTRACT(EPOCH FROM (",
        ttl_escaped, " AT TIME ZONE 'UTC' - CURRENT_TIMESTAMP AT TIME ZONE 'UTC'",
      "))) AS ", ttl_escaped
    }

    create_statement = concat {
      "CREATE TABLE IF NOT EXISTS ", table_name_escaped, " (\n",
      "  ",   concat(create_expressions, ",\n  "), "\n",
      ");\n", concat(foreign_key_indexes, "\n"), "\n",
      "CREATE INDEX IF NOT EXISTS ", ttl_index, " ON ", table_name_escaped, " (", ttl_escaped, ");",
    }

    insert_statement = concat {
      "INSERT INTO ",  table_name_escaped, " (", insert_columns, ")\n",
      "     VALUES (", insert_expressions, ")\n",
      "  RETURNING ",  select_expressions, ";",
    }

    upsert_statement = concat {
      "INSERT INTO ",  table_name_escaped, " (", insert_columns, ")\n",
      "     VALUES (", insert_expressions, ")\n",
      "ON CONFLICT (", pk_escaped, ") DO UPDATE\n",
      "        SET ",  upsert_expressions, "\n",
      "  RETURNING ",  select_expressions, ";",
    }


    update_statement = concat {
      "   UPDATE ",  table_name_escaped, "\n",
      "      SET ",  update_expressions, "\n",
      "    WHERE (", pk_escaped, ") = (", update_placeholders, ")\n",
      "      AND (", ttl_escaped, " IS NULL OR ", ttl_escaped, " >= CURRENT_TIMESTAMP AT TIME ZONE 'UTC')\n",
      "RETURNING ",  select_expressions, ";",
    }

    select_statement = concat {
      "SELECT ",  select_expressions, "\n",
      "  FROM ",  table_name_escaped, "\n",
      " WHERE (", pk_escaped, ") = (", primary_key_placeholders, ")\n",
      "   AND (", ttl_escaped, " IS NULL OR ", ttl_escaped, " >= CURRENT_TIMESTAMP AT TIME ZONE 'UTC')\n",
      " LIMIT 1;"
    }

    page_first_statement = concat {
      "  SELECT ",  select_expressions, "\n",
      "    FROM ",  table_name_escaped, "\n",
      "   WHERE (", ttl_escaped, " IS NULL OR ", ttl_escaped, " >= CURRENT_TIMESTAMP AT TIME ZONE 'UTC')\n",
      "ORDER BY ",  pk_escaped, "\n",
      "   LIMIT $1;";
    }

    page_next_statement = concat {
      "  SELECT ",  select_expressions, "\n",
      "    FROM ",  table_name_escaped, "\n",
      "   WHERE (", pk_escaped, ") > (", primary_key_placeholders, ")\n",
      "     AND (", ttl_escaped, " IS NULL OR ", ttl_escaped, " >= CURRENT_TIMESTAMP AT TIME ZONE 'UTC')\n",
      "ORDER BY ",  pk_escaped, "\n",
      "   LIMIT $", page_next_count, ";"
    }

    delete_statement = concat {
      "DELETE\n",
      "  FROM ",  table_name_escaped, "\n",
      " WHERE (", pk_escaped, ") = (", primary_key_placeholders, ")\n",
      "   AND (", ttl_escaped, " IS NULL OR ", ttl_escaped, " >= CURRENT_TIMESTAMP AT TIME ZONE 'UTC');",
    }

    count_statement = concat {
      "SELECT COUNT(*) AS ", escape_identifier(connector, "count"), "\n",
      "  FROM ",  table_name_escaped, "\n",
      " WHERE (", ttl_escaped, " IS NULL OR ", ttl_escaped, " >= CURRENT_TIMESTAMP AT TIME ZONE 'UTC')\n",
      " LIMIT 1;"
    }

    if foreign_key_indexes_count > 0 then
      drop_statement = concat {
        "DROP INDEX IF EXISTS ", ttl_index, ", ", concat(foreign_key_indexes_escaped, ", "), ";\n",
        "DROP TABLE IF EXISTS ", table_name_escaped, ";"
      }

    else
      drop_statement = concat {
        "DROP INDEX IF EXISTS ", ttl_index, ";\n",
        "DROP TABLE IF EXISTS ", table_name_escaped, ";"
      }
    end

  else
    insert_count = fields_count

    insert_expressions = concat(insert_expressions,  ", ")
    insert_columns = concat(insert_columns, ", ")

    update_expressions = concat(update_expressions, ", ")

    upsert_expressions = concat(upsert_expressions, ", ")

    create_statement = concat {
      "CREATE TABLE IF NOT EXISTS ", table_name_escaped, " (\n",
      "  ",   concat(create_expressions, ",\n  "), "\n",
      ");\n", concat(foreign_key_indexes, "\n")
    }

    insert_statement = concat {
      "INSERT INTO ",  table_name_escaped, " (", insert_columns, ")\n",
      "     VALUES (", insert_expressions, ")\n",
      "  RETURNING ", select_expressions, ";",
    }

    upsert_statement = concat {
      "INSERT INTO ",  table_name_escaped, " (", insert_columns, ")\n",
      "     VALUES (", insert_expressions, ")\n",
      "ON CONFLICT (", pk_escaped, ") DO UPDATE\n",
      "        SET ",  upsert_expressions, "\n",
      "  RETURNING ", select_expressions, ";",
    }

    update_statement = concat {
      "   UPDATE ",  table_name_escaped, "\n",
      "      SET ",  update_expressions, "\n",
      "    WHERE (", pk_escaped, ") = (", update_placeholders, ")\n",
      "RETURNING ", select_expressions, ";",
    }

    select_statement = concat {
      "SELECT ",  select_expressions, "\n",
      "  FROM ",  table_name_escaped, "\n",
      " WHERE (", pk_escaped, ") = (", primary_key_placeholders, ")\n",
      " LIMIT 1;"
    }

    page_first_statement = concat {
      "  SELECT ", select_expressions, "\n",
      "    FROM ", table_name_escaped, "\n",
      "ORDER BY ", pk_escaped, "\n",
      "   LIMIT $1;";
    }

    page_next_statement = concat {
      "  SELECT ",  select_expressions, "\n",
      "    FROM ",  table_name_escaped, "\n",
      "   WHERE (", pk_escaped, ") > (", primary_key_placeholders, ")\n",
      "ORDER BY ",  pk_escaped, "\n",
      "   LIMIT $", page_next_count, ";"
    }

    delete_statement = concat {
      "DELETE\n",
      "  FROM ",  table_name_escaped, "\n",
      " WHERE (", pk_escaped, ") = (", primary_key_placeholders, ");",
    }

    count_statement = concat {
      "SELECT COUNT(*) AS ", escape_identifier(connector, "count"), "\n",
      "  FROM ", table_name_escaped, "\n",
      " LIMIT 1;"
    }

    if foreign_key_indexes_count > 0 then
      drop_statement = concat {
        "DROP INDEX IF EXISTS ", concat(foreign_key_indexes_escaped, ", "), ";\n",
        "DROP TABLE IF EXISTS ", table_name_escaped, " CASCADE;"
      }

    else
      drop_statement = concat {
        "DROP TABLE IF EXISTS ", table_name_escaped, " CASCADE;"
      }
    end
  end

  if composite_cache_key then
    create_statement = concat { create_statement, "\n",
      "CREATE INDEX IF NOT EXISTS ", cache_key_index,
      " ON ", table_name_escaped, " (", cache_key_escaped, ");"
    }
  end

  local truncate_statement = concat {
    "TRUNCATE ", table_name_escaped, " RESTART IDENTITY CASCADE;"
  }

  local primary_key_args = new_tab(primary_key_count, 0)
  local insert_args      = new_tab(insert_count, 0)
  local update_args      = new_tab(update_args_count, 0)
  local single_args      = new_tab(1, 0)
  local page_next_args   = new_tab(page_next_count, 0)

  local self = setmetatable({
    connector    = connector,
    schema       = schema,
    errors       = errors,
    expand       = foreign_key_count > 0 and
                   expand(table_name .. "_expand", foreign_key_list) or
                   noop,
    collapse     = collapse(table_name .. "_collapse", foreign_key_list),
    fields       = fields_hash,
    statements   = {
      create     = create_statement,
      truncate   = truncate_statement,
      count      = count_statement,
      drop       = drop_statement,
      insert     = {
        expr     = insert_expressions,
        cols     = insert_columns,
        argn     = insert_names,
        argc     = insert_count,
        argv     = insert_args,
        make     = compile(table_name .. "_insert", insert_statement),
      },
      upsert     = {
        expr     = upsert_expressions,
        argn     = insert_names,
        argc     = insert_count,
        argv     = insert_args,
        make     = compile(table_name .. "_upsert", upsert_statement),
      },
      update     = {
        expr     = update_expressions,
        argn     = update_args_names,
        argc     = update_args_count,
        argv     = update_args,
        make     = compile(table_name .. "_update", update_statement),
      },
      delete     = {
        argn     = primary_key_names,
        argc     = primary_key_count,
        argv     = primary_key_args,
        make     = compile(table_name .. "_delete", delete_statement),
      },
      select     = {
        expr     = select_expressions,
        argn     = primary_key_names,
        argc     = primary_key_count,
        argv     = primary_key_args,
        make     = compile(table_name .. "_select" , select_statement),
      },
      page_first = {
        argn     = { LIMIT },
        argc     = 1,
        argv     = single_args,
        make     = compile(table_name .. "_first" , page_first_statement),
      },
      page_next  = {
        argn     = page_next_names,
        argc     = page_next_count,
        argv     = page_next_args,
        make     = compile(table_name .. "_next" , page_next_statement),
      },
    },
  }, _mt)

  if foreign_key_count > 0 then
    local statements = self.statements

    for foreign_entity_name, foreign_key in pairs(foreign_keys) do
      local fk_names   = foreign_key.names
      local fk_escaped = foreign_key.escaped
      local fk_count   = foreign_key.count

      local fk_placeholders = {}
      local pk_placeholders = {}

      local foreign_key_names = concat(fk_escaped, ", ")

      local argc_first = fk_count + 1
      local argv_first = new_tab(argc_first, 0)
      local argn_first = new_tab(argc_first, 0)
      local argc_next  = argc_first + primary_key_count
      local argv_next  = new_tab(argc_next, 0)
      local argn_next  = new_tab(argc_next, 0)

      for i = 1, fk_count do
        argn_first[i]      = fk_names[i]
        argn_next[i]       = fk_names[i]
        fk_placeholders[i] = "$" .. i
      end

      for i = 1, primary_key_count do
        local index = i + fk_count
        argn_next[index]   = primary_key_names[i]
        pk_placeholders[i] = "$" .. index
      end

      argn_first[argc_first] = LIMIT
      argn_next[argc_next]   = LIMIT

      fk_placeholders = concat(fk_placeholders, ", ")
      pk_placeholders = concat(pk_placeholders, ", ")

      if ttl then
        page_first_statement = concat {
          "  SELECT ",  select_expressions, "\n",
          "    FROM ",  table_name_escaped, "\n",
          "   WHERE (", foreign_key_names, ") = (", fk_placeholders, ")\n",
          "     AND (", ttl_escaped, " IS NULL OR ", ttl_escaped, " >= CURRENT_TIMESTAMP AT TIME ZONE 'UTC')\n",
          "ORDER BY ",  pk_escaped, "\n",
          "   LIMIT $", argc_first, ";";
        }

        page_next_statement = concat {
          "  SELECT ",  select_expressions, "\n",
          "    FROM ",  table_name_escaped, "\n",
          "   WHERE (", foreign_key_names, ") = (", fk_placeholders, ")\n",
          "     AND (", pk_escaped, ") > (", pk_placeholders, ")\n",
          "     AND (", ttl_escaped, " IS NULL OR ", ttl_escaped, " >= CURRENT_TIMESTAMP AT TIME ZONE 'UTC')\n",
          "ORDER BY ",  pk_escaped, "\n",
          "   LIMIT $", argc_next, ";"
        }

      else
        page_first_statement = concat {
          "  SELECT ",  select_expressions, "\n",
          "    FROM ",  table_name_escaped, "\n",
          "   WHERE (", foreign_key_names, ") = (", fk_placeholders, ")\n",
          "ORDER BY ",  pk_escaped, "\n",
          "   LIMIT $", argc_first, ";";
        }

        page_next_statement = concat {
          "  SELECT ",  select_expressions, "\n",
          "    FROM ",  table_name_escaped, "\n",
          "   WHERE (", foreign_key_names, ") = (", fk_placeholders, ")\n",
          "     AND (", pk_escaped, ") > (", pk_placeholders, ")\n",
          "ORDER BY ",  pk_escaped, "\n",
          "   LIMIT $", argc_next, ";"
        }
      end

      local statement_name = "page_for_" .. foreign_entity_name

      statements[statement_name .. "_first"] = {
        argn = argn_first,
        argc = argc_first,
        argv = argv_first,
        make = compile(concat({ table_name, statement_name, "first" }, "_"), page_first_statement),
      }

      statements[statement_name .. "_next"] = {
        argn = argn_next,
        argc = argc_next,
        argv = argv_next,
        make = compile(concat({ table_name, statement_name, "next" }, "_"), page_next_statement)
      }

      self[statement_name] = make_select_for(foreign_entity_name)
    end
  end

  if tags then
    local statements = self.statements
    local pk_placeholders = {}

    local argc_first = 2
    local argv_first = new_tab(argc_first, 0)
    local argn_first = new_tab(argc_first, 0)
    local argc_next  = argc_first + primary_key_count
    local argv_next  = new_tab(argc_next, 0)
    local argn_next  = new_tab(argc_next, 0)

    for i = 1, primary_key_count do
      local index = i + 1
      argn_next[index]   = primary_key_names[i]
      pk_placeholders[i] = "$" .. index
    end

    pk_placeholders = concat(pk_placeholders, ", ")

    argn_first[1] = "tags"
    argn_first[argc_first] = LIMIT
    argn_next[1] = "tags"
    argn_next[argc_next] = LIMIT

    local page_first_by_tags_statement
    local page_next_by_tags_statement

    for cond, op in pairs({["_and"] = "@>", ["_or"] = "&&"}) do

      if ttl then
        page_first_by_tags_statement = concat {
          "  SELECT ",  select_expressions, "\n",
          "    FROM ",  table_name_escaped, "\n",
          "   WHERE tags ", op, " $1\n",
          "     AND (", ttl_escaped, " IS NULL OR ", ttl_escaped, " >= CURRENT_TIMESTAMP AT TIME ZONE 'UTC')\n",
          "ORDER BY ",  pk_escaped, "\n",
          "   LIMIT $2;";
        }

        page_next_by_tags_statement = concat {
          "  SELECT ",  select_expressions, "\n",
          "    FROM ",  table_name_escaped, "\n",
          "   WHERE tags ", op, " $1\n",
          "     AND (", pk_escaped, ") > (", pk_placeholders, ")\n",
          "     AND (", ttl_escaped, " IS NULL OR ", ttl_escaped, " >= CURRENT_TIMESTAMP AT TIME ZONE 'UTC')\n",
          "ORDER BY ",  pk_escaped, "\n",
          "   LIMIT $", argc_next, ";"
        }
      else
        page_first_by_tags_statement = concat {
          "  SELECT ",  select_expressions, "\n",
          "    FROM ",  table_name_escaped, "\n",
          "   WHERE tags ", op, " $1\n",
          "ORDER BY ",  pk_escaped, "\n",
          "   LIMIT $2;";
        }

        page_next_by_tags_statement = concat {
          "  SELECT ",  select_expressions, "\n",
          "    FROM ",  table_name_escaped, "\n",
          "   WHERE tags ", op, " $1\n",
          "     AND (", pk_escaped, ") > (", pk_placeholders, ")\n",
          "ORDER BY ",  pk_escaped, "\n",
          "   LIMIT $", argc_next, ";"
        }
      end

      local statement_name = "page_by_tags"

      statements[statement_name .. cond .. "_first"] = {
        argn = argn_first,
        argc = argc_first,
        argv = argv_first,
        make = compile(concat({ table_name, statement_name, "first" }, "_"), page_first_by_tags_statement),
      }

      statements[statement_name .. cond .. "_next"] = {
        argn = argn_next,
        argc = argc_next,
        argv = argv_next,
        make = compile(concat({ table_name, statement_name, "next" }, "_"), page_next_by_tags_statement)
      }
    end
  end

  if composite_cache_key then
    unique_fields_count = unique_fields_count + 1
    insert(unique_fields, {
      name = "cache_key",
      name_escaped = escape_identifier(connector, "cache_key"),
    })
  end

  if unique_fields_count > 0 then
    local update_by_args_count = update_fields_count + 1
    local update_by_args = new_tab(update_by_args_count, 0)
    local statements = self.statements

    for i = 1, unique_fields_count do
      local unique_field   = unique_fields[i]
      local field_name     = unique_field.field_name or unique_field.name
      local unique_name    = unique_field.name
      local unique_escaped = unique_field.name_escaped
      local single_names   = { unique_name }

      local select_by_statement_name = "select_by_" .. field_name
      local select_by_statement

      if ttl then
        select_by_statement = concat {
          "SELECT ",  select_expressions, "\n",
          "  FROM ",  table_name_escaped, "\n",
          " WHERE ",  unique_escaped, " = $1\n",
          "   AND (", ttl_escaped, " IS NULL OR ", ttl_escaped, " >= CURRENT_TIMESTAMP AT TIME ZONE 'UTC')\n",
          " LIMIT 1;"
        }

      else
        select_by_statement = concat {
          "SELECT ", select_expressions, "\n",
          "  FROM ", table_name_escaped, "\n",
          " WHERE ", unique_escaped, " = $1\n",
          " LIMIT 1;"
        }
      end

      statements[select_by_statement_name] = {
        argn = single_names,
        argc = 1,
        argv = single_args,
        make = compile(concat({ table_name, select_by_statement_name }, "_"), select_by_statement),
      }

      local update_by_statement_name = "update_by_" .. field_name
      local update_by_statement

      if ttl then
        update_by_statement = concat {
          "   UPDATE ",  table_name_escaped, "\n",
          "      SET ",  update_expressions, "\n",
          "    WHERE ",  unique_escaped, " = $", update_by_args_count, "\n",
          "      AND (", ttl_escaped, " IS NULL OR ", ttl_escaped, " >= CURRENT_TIMESTAMP AT TIME ZONE 'UTC')\n",
          "RETURNING ", select_expressions, ";",
        }
      else
        update_by_statement = concat {
          "   UPDATE ", table_name_escaped, "\n",
          "      SET ", update_expressions, "\n",
          "    WHERE ", unique_escaped, " = $", update_by_args_count, "\n",
          "RETURNING ", select_expressions, ";",
        }
      end

      local update_by_args_names = {}
      for i = 1, update_fields_count do
        update_by_args_names[i] = update_names[i]
      end

      update_by_args_names[update_by_args_count] = unique_name
      statements[update_by_statement_name] = {
        argn = update_by_args_names,
        argc = update_by_args_count,
        argv = update_by_args,
        make = compile(concat({ table_name, update_by_statement_name }, "_"), update_by_statement),
      }

      local upsert_by_statement_name = "upsert_by_" .. field_name
      local conflict_key = unique_escaped
      if composite_cache_key then
        conflict_key = escape_identifier(connector, "cache_key")
      end
      local upsert_by_statement = concat {
        "INSERT INTO ",  table_name_escaped, " (", insert_columns, ")\n",
        "     VALUES (", insert_expressions, ")\n",
        "ON CONFLICT (", conflict_key, ") DO UPDATE\n",
        "        SET ",  upsert_expressions, "\n",
        "  RETURNING ",  select_expressions, ";",
      }


      statements[upsert_by_statement_name] = {
        argn = insert_names,
        argc = insert_count,
        argv = insert_args,
        make = compile(concat({ table_name, upsert_by_statement_name }, "_"), upsert_by_statement),
      }

      local delete_by_statement_name = "delete_by_" .. field_name
      local delete_by_statement

      if ttl then
        delete_by_statement = concat {
          "DELETE\n",
          "  FROM ",  table_name_escaped, "\n",
          " WHERE ",  unique_escaped, " = $1\n",
          "   AND (", ttl_escaped, " IS NULL OR ", ttl_escaped, " >= CURRENT_TIMESTAMP AT TIME ZONE 'UTC');",
        }

      else
        delete_by_statement = concat {
          "DELETE\n",
          "  FROM ", table_name_escaped, "\n",
          " WHERE ", unique_escaped, " = $1;",
        }
      end

      statements[delete_by_statement_name] = {
        argn = single_names,
        argc = 1,
        argv = single_args,
        make = compile(concat({ table_name, delete_by_statement_name }, "_"), delete_by_statement),
      }
    end
  end

  return self
end


return _M
