local declarative_config = require "kong.db.schema.others.declarative_config"
local workspaces = require "kong.workspaces"
local lmdb = require("resty.lmdb")
local marshaller = require("kong.db.declarative.marshaller")



local kong = kong
local fmt = string.format
local type = type
local next = next
local pairs = pairs
local tostring = tostring
local tonumber = tonumber
local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64
local null          = ngx.null
local unmarshall    = marshaller.unmarshall
local lmdb_get      = lmdb.get


local off = {}


local _mt = {}
_mt.__index = _mt


local function ws(self, options)
  if not self.schema.workspaceable then
    return ""
  end

  if options then
    if options.workspace == null then
      return "*"
    end
    if options.workspace then
      return options.workspace
    end
  end
  return workspaces.get_workspace_id() or kong.default_workspace
end


-- Returns a dict of entity_ids tagged according to the given criteria.
-- Currently only the following kinds of keys are supported:
-- * A key like `services|<ws_id>|@list` will only return service keys
-- @tparam string the key to be used when filtering
-- @tparam table tag_names an array of tag names (strings)
-- @tparam string|nil tags_cond either "or", "and". `nil` means "or"
-- @treturn table|nil returns a table with entity_ids as values, and `true` as keys
local function get_entity_ids_tagged(key, tag_names, tags_cond)
  local tag_name, list, err
  local dict = {} -- keys are entity_ids, values are true

  for i = 1, #tag_names do
    tag_name = tag_names[i]
    list, err = unmarshall(lmdb_get("taggings:" .. tag_name .. "|" .. key))
    if err then
      return nil, err
    end

    list = list or {}

    if i > 1 and tags_cond == "and" then
      local list_len = #list
      -- optimization: exit early when tags_cond == "and" and one of the tags does not return any entities
      if list_len == 0 then
        return {}
      end

      local and_dict = {}
      local new_tag_id
      for i = 1, list_len do
        new_tag_id = list[i]
        and_dict[new_tag_id] = dict[new_tag_id] -- either true or nil
      end
      dict = and_dict

      -- optimization: exit early when tags_cond == "and" and current list is empty
      if not next(dict) then
        return {}
      end

    else -- tags_cond == "or" or first iteration
      -- the first iteration is the same for both "or" and "and": put all ids into dict
      for i = 1, #list do
        dict[list[i]] = true
      end
    end
  end

  local arr = {}
  local len = 0
  for entity_id in pairs(dict) do
    len = len + 1
    arr[len] = entity_id
  end
  table.sort(arr) -- consistency when paginating results

  return arr
end


local function page_for_key(self, key, size, offset, options)
  if not size then
    size = self.connector:get_page_size(options)
  end

  if offset then
    local token = decode_base64(offset)
    if not token then
      return nil, self.errors:invalid_offset(offset, "bad base64 encoding")
    end

    local number = tonumber(token)
    if not number then
      return nil, self.errors:invalid_offset(offset, "invalid offset")
    end

    offset = number

  else
    offset = 1
  end

  local list, err
  if options and options.tags then
    list, err = get_entity_ids_tagged(key, options.tags, options.tags_cond)
    if err then
      return nil, err
    end

  else
    list, err = unmarshall(lmdb_get(key))
    if err then
      return nil, err
    end

    list = list or {}
  end

  local ret = {}
  local schema_name = self.schema.name

  local item
  for i = offset, offset + size - 1 do
    item = list[i]
    if not item then
      offset = nil
      break
    end

    -- Tags are stored in the cache entries "tags||@list" and "tags:<tagname>|@list"
    -- The contents of both of these entries is an array of strings
    -- Each of these strings has the form "<tag>|<entity_name>|<entity_id>"
    -- For example "admin|services|<a service uuid>"
    -- This loop transforms each individual string into tables.
    if schema_name == "tags" then
      local tag_name, entity_name, uuid = string.match(item, "^([^|]+)|([^|]+)|(.+)$")
      if not tag_name then
        return nil, "Could not parse tag from cache: " .. tostring(item)
      end

      item = { tag = tag_name, entity_name = entity_name, entity_id = uuid }

    -- The rest of entities' lists (i.e. "services|<ws_id>|@list") only contain ids, so in order to
    -- get the entities we must do an additional cache access per entry
    else
      item, err = unmarshall(lmdb_get(item))
      if err then
        return nil, err
      end
    end

    if not item then
      return nil, "stale data detected while paginating"
    end

    item = self.schema:process_auto_fields(item, "select", true, {
      no_defaults = true,
      show_ws_id = true,
    })

    ret[i - offset + 1] = item
  end

  if offset then
    return ret, nil, encode_base64(tostring(offset + size), true)
  end

  return ret
end


local function select_by_key(self, key)
  local entity, err = unmarshall(lmdb_get(key))
  if not entity then
    return nil, err
  end

  entity =  self.schema:process_auto_fields(entity, "select", true, {
    no_defaults = true,
    show_ws_id = true,
  })

  return entity
end


local function page(self, size, offset, options)
  local ws_id = ws(self, options)
  local key = self.schema.name .. "|" .. ws_id .. "|@list"
  return page_for_key(self, key, size, offset, options)
end


local function select(self, pk, options)
  local ws_id = ws(self, options)
  local id = declarative_config.pk_string(self.schema, pk)
  local key = self.schema.name .. ":" .. id .. ":::::" .. ws_id
  return select_by_key(self, key)
end


local function select_by_field(self, field, value, options)
  if type(value) == "table" then
    local _
    _, value = next(value)
  end

  local ws_id = ws(self, options)

  local key
  if field ~= "cache_key" then
    local unique_across_ws = self.schema.fields[field].unique_across_ws
    if unique_across_ws then
      ws_id = ""
    end

    -- only accept global query by field if field is unique across workspaces
    assert(not options or options.workspace ~= null or unique_across_ws)

    key = self.schema.name .. "|" .. ws_id .. "|" .. field .. ":" .. value

  else
    -- if select_by_cache_key, use the provided cache_key as key directly
    key = value
  end

  return select_by_key(self, key)
end

do
  local unsupported = function(operation)
    return function(self)
      local err = fmt("cannot %s '%s' entities when not using a database",
                      operation, self.schema.name)
      return nil, self.errors:operation_unsupported(err)
    end
  end

  local unsupported_by = function(operation)

    return function(self, field_name)
      local err = fmt("cannot %s '%s' entities by '%s' when not using a database",
                      operation, self.schema.name, '%s')
      return nil, self.errors:operation_unsupported(fmt(err, field_name))
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
  -- off-strategy specific methods:
  _mt.page_for_key = page_for_key
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

  local name = self.schema.name
  for fname, fdata in schema:each_field() do
    if fdata.type == "foreign" then
      local entity = fdata.reference
      local method = "page_for_" .. fname
      self[method] = function(_, foreign_key, size, offset, options)
        local ws_id = ws(self, options)

        local key = name .. "|" .. ws_id .. "|" .. entity .. "|" .. foreign_key.id .. "|@list"
        return page_for_key(self, key, size, offset, options)
      end
    end
  end

  return setmetatable(self, _mt)
end


return off
