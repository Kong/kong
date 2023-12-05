local declarative_config = require("kong.db.schema.others.declarative_config")
local workspaces = require("kong.workspaces")
local lmdb = require("resty.lmdb")
local lmdb_prefix = require("resty.lmdb.prefix")
local lmdb_transaction = require("resty.lmdb.transaction")
local marshaller = require("kong.db.declarative.marshaller")
local yield = require("kong.tools.yield").yield
local declarative = require("kong.db.declarative")

local kong = kong
local string_format = string.format
local type = type
local next = next
local sort = table.sort
local pairs = pairs
local match = string.match
local assert = assert
local tostring = tostring
local tonumber = tonumber
local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64
local null = ngx.null
local unmarshall = marshaller.unmarshall
local marshall = marshaller.marshall
local lmdb_get = lmdb.get
local get_workspace_id = workspaces.get_workspace_id
local pk_string = declarative_config.pk_string
local unique_field_key = declarative.unique_field_key
local foreign_field_key = declarative.foreign_field_key


local PROCESS_AUTO_FIELDS_OPTS = {
  no_defaults = true,
  show_ws_id = true,
}


local off = {}


local _mt = {}
_mt.__index = _mt


local function ws(schema, options)
  if not schema.workspaceable then
    return kong.default_workspace
  end

  if options then
    -- options.workspace == null must be handled by caller by querying
    -- all available workspaces one by one
    if options.workspace == null then
      return kong.default_workspace
    end

    if options.workspace then
      return options.workspace
    end
  end

  return get_workspace_id()
end


local function process_ttl_field(entity)
  if entity and entity.ttl and entity.ttl ~= null then
    local ttl_value = entity.ttl - ngx.time()
    if ttl_value > 0 then
      entity.ttl = ttl_value

    else
      entity = nil  -- do not return the expired entity
    end
  end

  return entity
end


local function construct_entity(schema, value)
  local entity, err = unmarshall(value)
  if not entity then
    return nil, err
  end

  if schema.ttl then
    entity = process_ttl_field(entity)
    if not entity then
      return nil
    end
  end

  entity = schema:process_auto_fields(entity, "select", true, PROCESS_AUTO_FIELDS_OPTS)

  return entity
end


-- select item by key, if follow is true, then one indirection will be followed
local function select_by_key(schema, key, follow)
  if follow then
    local actual_key, err = lmdb_get(key)
    if not actual_key then
        return nil, err
    end

    return select_by_key(schema, actual_key, false)

  else
    local entity, err = construct_entity(schema, lmdb_get(key))
    if not entity then
      return nil, err
    end

    return entity
  end
end


local function page_for_prefix(self, prefix, size, offset, options, follow)
  if not size then
    size = self.connector:get_page_size(options)
  end

  offset = offset or prefix

  local list = {}

  local ret = {}
  local ret_idx = 0
  local schema = self.schema

  local res, err_or_more = lmdb_prefix.page(offset, prefix, nil, size)
  if not res then
    return nil, err_or_more
  end

  local last_key

  for i, kv in ipairs(res) do
    last_key = kv.key
    local item, err

    if follow then
      item, err = select_by_key(schema, kv.value, false)
      if err then
        return nil, err
      end

    else
      item, err = construct_entity(schema, kv.value)
      if not item then
        return nil, err
      end
    end

    if item then
      ret_idx = ret_idx + 1
      ret[ret_idx] = item
    end
  end

  if err_or_more then
    return ret, nil, last_key
  end

  return ret
end


local function page(self, size, offset, options)
  local schema = self.schema
  local ws_id = ws(schema, options)
  local prefix = string_format("%s|%s|*|", schema.name, ws_id)
  return page_for_prefix(self, prefix, size, offset, options, false)
end


-- select by primary key
local function select(self, pk, options)
  local schema = self.schema
  local ws_id = ws(schema, options)
  local pk = pk_string(schema, pk)
  local key = string_format("%s|%s|*|%s", schema.name, ws_id, pk)
  return select_by_key(schema, key, false)
end


-- select by unique field (including select_by_cache_key)
-- the DAO guarentees this method only gets called for unique fields
local function select_by_field(self, field, value, options)
  local schema = self.schema

  if type(value) == "table" then
    -- select by foreign, we only support one key for now (no composites)
    local fdata = schema.fields[field]
    assert(fdata.type == "foreign")
    assert(#kong.db[fdata.reference].schema.primary_key == 1)

    local _
    _, value = next(value)
  end

  local ws_id = ws(schema, options)

  local key
  local unique_across_ws = schema.fields[field].unique_across_ws
  -- only accept global query by field if field is unique across workspaces
  assert(not options or options.workspace ~= null or unique_across_ws)

  if unique_across_ws then
    ws_id = kong.default_workspace
  end

  key = unique_field_key(schema.name, ws_id, field, value)

  return select_by_key(schema, key, true)
end


local function delete(self, pk, options)
  local schema = self.schema

  local entity, err = select(self, pk, options)
  if not entity then
    return nil, err
  end

  local t = lmdb_transaction.begin(16)

  local pk = pk_string(schema, pk)
  local ws_id = ws(schema, options)
  local entity_name = schema.name
  local item_key = string_format("%s|%s|*|%s", entity_name, ws_id, pk)
  t:set(item_key, nil)

  local dao = kong.db[entity_name]

  -- select_by_cache_key
  if schema.cache_key then
    local cache_key = dao:cache_key(entity)
    local key = unique_field_key(entity_name, ws_id, "cache_key", cache_key)
    t:set(key, nil)
  end

  for fname, fdata in schema:each_field() do
    local is_foreign = fdata.type == "foreign"
    local fdata_reference = fdata.reference
    local value = entity[fname]

    if value and value ~= null then
      if fdata.unique then
        -- unique and not a foreign key, or is a foreign key, but non-composite
        if type(value) == "table" then
          assert(is_foreign)
          value = pk_string(kong.db[fdata_reference].schema, value)
        end

        if fdata.unique_across_ws then
          ws_id = default_workspace_id
        end

        local key = unique_field_key(entity_name, ws_id, fname, value)
        t:set(key, nil)

      elseif is_foreign then
        -- not unique and is foreign, generate page_for_foo indexes
        assert(type(value) == "table")
        value = pk_string(kong.db[fdata_reference].schema, value)

        local key = foreign_field_key(entity_name, ws_id, fname, value, pk)
        t:set(key, nil)
      end
    end
  end

  local res, err = t:commit()
  if not res then
    return nil, self.errors:database_error(err)
  end

  return true
end


local function remove_nulls(tbl)
  for k,v in pairs(tbl) do
    if v == null then
      tbl[k] = nil

    elseif type(v) == "table" then
      tbl[k] = remove_nulls(v)
    end
  end
  return tbl
end


local function insert(self, item, options)
  local schema = self.schema
  local t = lmdb_transaction.begin(16)

  local pk = pk_string(schema, item)
  local entity_name = schema.name
  local ws_id = ws(schema, options)
  local dao = kong.db[entity_name]

  local item_key = string_format("%s|%s|*|%s", entity_name, ws_id, pk)
  item = remove_nulls(item)

  local item_marshalled, err = marshall(item)
  if not item_marshalled then
    return nil, err
  end

  t:set(item_key, item_marshalled)

  -- select_by_cache_key
  if schema.cache_key then
    local cache_key = dao:cache_key(item)
    local key = unique_field_key(entity_name, ws_id, "cache_key", cache_key)
    t:set(key, item_key)
  end

  for fname, fdata in schema:each_field() do
    local is_foreign = fdata.type == "foreign"
    local fdata_reference = fdata.reference
    local value = item[fname]

    if value then
      if fdata.unique then
        -- unique and not a foreign key, or is a foreign key, but non-composite
        if type(value) == "table" then
          assert(is_foreign)
          value = pk_string(kong.db[fdata_reference].schema, value)
        end

        if fdata.unique_across_ws then
          ws_id = default_workspace_id
        end

        local key = unique_field_key(entity_name, ws_id, fname, value)
        t:set(key, item_key)

      elseif is_foreign then
        -- not unique and is foreign, generate page_for_foo indexes
        assert(type(value) == "table")
        value = pk_string(kong.db[fdata_reference].schema, value)

        local key = foreign_field_key(entity_name, ws_id, fname, value, pk)
        t:set(key, item_key)
      end
    end
  end

  local res, err = t:commit()
  if not res then
    return nil, self.errors:database_error(err)
  end

  return item
end


do
  local unsupported = function(operation)
    return function(self)
      local err = string_format("cannot %s '%s' entities when not using a database",
                      operation, self.schema.name)
      return nil, self.errors:operation_unsupported(err)
    end
  end

  local unsupported_by = function(operation)
    return function(self, field_name)
      local err = string_format("cannot %s '%s' entities by '%s' when not using a database",
                      operation, self.schema.name, '%s')
      return nil, self.errors:operation_unsupported(string_format(err, field_name))
    end
  end

  _mt.select = select
  _mt.page = page
  _mt.select_by_field = select_by_field
  _mt.insert = insert
  _mt.update = unsupported("update")
  _mt.upsert = unsupported("create or update")
  _mt.delete = delete
  _mt.update_by_field = unsupported_by("update")
  _mt.upsert_by_field = unsupported_by("create or update")
  _mt.delete_by_field = unsupported_by("remove")
  _mt.truncate = function() return true end
end


function off.new(connector, schema, errors)
  local self = {
    connector = connector, -- instance of kong.db.strategies.off.connector
    schema = schema,
    errors = errors,
  }

  if not kong.default_workspace then
    -- This is not the id for the default workspace in DB-less.
    -- This is a sentinel value for the init() phase before
    -- the declarative config is actually loaded.
    kong.default_workspace = "00000000-0000-0000-0000-000000000000"
  end

  local name = schema.name
  for fname, fdata in schema:each_field() do
    if fdata.type == "foreign" then
      local method = "page_for_" .. fname
      self[method] = function(_, foreign_key, size, offset, options)
        local ws_id = ws(schema, options)
        local prefix = foreign_field_key(name, ws_id, fname, foreign_key.id)
        ngx.log(ngx.ERR, method, " ", prefix)
        return page_for_prefix(self, prefix, size, offset, options, true)
      end
    end
  end

  return setmetatable(self, _mt)
end


return off
