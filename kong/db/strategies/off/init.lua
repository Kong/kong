local declarative_config = require("kong.db.schema.others.declarative_config")
--local workspaces = require("kong.workspaces")
local lmdb = require("resty.lmdb")
local lmdb_prefix = require("resty.lmdb.prefix")
--local lmdb_transaction = require("resty.lmdb.transaction")
local marshaller = require("kong.db.declarative.marshaller")
--local yield = require("kong.tools.yield").yield
local declarative = require("kong.db.declarative")

local kong = kong
local string_format = string.format
local type = type
local next = next
--local sort = table.sort
--local pairs = pairs
--local match = string.match
local assert = assert
--local tostring = tostring
--local tonumber = tonumber
local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64
local null = ngx.null
local unmarshall = marshaller.unmarshall
--local marshall = marshaller.marshall
local lmdb_get = lmdb.get
--local get_workspace_id = workspaces.get_workspace_id
local pk_string = declarative_config.pk_string
local unique_field_key = declarative.unique_field_key
local item_key = declarative.item_key
local item_key_prefix = declarative.item_key_prefix
local workspace_id = declarative.workspace_id
local foreign_field_key_prefix = declarative.foreign_field_key_prefix


local PROCESS_AUTO_FIELDS_OPTS = {
  no_defaults = true,
  show_ws_id = true,
}


local off = {}


local _mt = {}
_mt.__index = _mt


local UNINIT_WORKSPACE_ID = "00000000-0000-0000-0000-000000000000"


local function get_default_workspace()
  local ws_id = kong.default_workspace

  if ws_id == UNINIT_WORKSPACE_ID then
    local res = assert(kong.db.workspaces:select_by_name("default"))
    ws_id = res.id
  end

  return ws_id
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


-- select item by primary key, if follow is true, then one indirection
-- will be followed indirection means the value of `key` is not the actual
-- serialized item, but rather the value is a pointer to the key where
-- actual serialized item is located. This way this function can be shared
-- by both primary key lookup as well as unique key lookup without needing
-- to duplicate the item content
local function select_by_key(schema, key, follow)
  if follow then
    local actual_key, err = lmdb_get(key)
    if not actual_key then
        return nil, err
    end

    return select_by_key(schema, actual_key, false)
  end

  local entity, err = construct_entity(schema, lmdb_get(key))
  if not entity then
    return nil, err
  end

  return entity
end


local function page_for_prefix(self, prefix, size, offset, options, follow)
  if not size then
    size = self.connector:get_page_size(options)
  end

  offset = offset or prefix

  --local list = {}

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

    else
      item, err = construct_entity(schema, kv.value)
    end

    if err then
      return nil, err
    end

    ret_idx = ret_idx + 1
    ret[ret_idx] = item
  end

  if err_or_more then
    return ret, nil, encode_base64(last_key .. "\x00", true)
  end

  return ret
end


local function page(self, size, offset, options)
  local schema = self.schema
  local ws_id = workspace_id(schema, options)
  local prefix = item_key_prefix(schema.name, ws_id)

  if offset then
    local token = decode_base64(offset)
    if not token then
      return nil, self.errors:invalid_offset(offset, "bad base64 encoding")
    end

    --local number = tonumber(token)
    --if not number then
    --  return nil, self.errors:invalid_offset(offset, "invalid offset")
    --end

    offset = token

  end

  return page_for_prefix(self, prefix, size, offset, options, false)
end


-- select by primary key
local function select(self, pk, options)
  local schema = self.schema
  local ws_id = workspace_id(schema, options)
  local pk = pk_string(schema, pk)
  local key = item_key(schema.name, ws_id, pk)
  return select_by_key(schema, key, false)
end


-- select by unique field (including select_by_cache_key)
-- the DAO guarantees this method only gets called for unique fields
-- see: validate_foreign_key_is_single_primary_key
local function select_by_field(self, field, value, options)
  local schema = self.schema

  if type(value) == "table" then
    -- select by foreign, DAO only support one key for now (no composites)
    local fdata = schema.fields[field]
    assert(fdata.type == "foreign")
    assert(#kong.db[fdata.reference].schema.primary_key == 1)

    local _
    _, value = next(value)
  end

  local ws_id = workspace_id(schema, options)

  local key
  local unique_across_ws = schema.fields[field].unique_across_ws
  -- only accept global query by field if field is unique across workspaces
  assert(not options or options.workspace ~= null or unique_across_ws)

  if unique_across_ws then
    ws_id = get_default_workspace()
  end

  key = unique_field_key(schema.name, ws_id, field, value)

  return select_by_key(schema, key, true)
end


--[[
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
--]]


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
  _mt.insert = unsupported("create")
  _mt.update = unsupported("update")
  _mt.upsert = unsupported("create or update")
  _mt.delete = unsupported("remove")
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
    kong.default_workspace = UNINIT_WORKSPACE_ID
  end

  local name = schema.name
  for fname, fdata in schema:each_field() do
    if fdata.type == "foreign" then
      local method = "page_for_" .. fname
      self[method] = function(_, foreign_key, size, offset, options)
        local ws_id = workspace_id(schema, options)
        local prefix = foreign_field_key_prefix(name, ws_id, fname, foreign_key.id)
        return page_for_prefix(self, prefix, size, offset, options, true)
      end
    end
  end

  return setmetatable(self, _mt)
end


return off
