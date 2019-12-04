local declarative_config = require "kong.db.schema.others.declarative_config"


local kong = kong
local fmt = string.format
local type = type
local next = next
local pairs = pairs
local tostring = tostring
local tonumber = tonumber
local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64


local off = {}


local _mt = {}
_mt.__index = _mt


local function empty_list_cb()
  return {}
end


local function nil_cb()
  return nil
end

-- Returns a dict of entity_ids tagged according to the given criteria.
-- Currently only the following kinds of keys are supported:
-- * A key like `services|list` will only return service ids
-- @tparam string the key to be used when filtering
-- @tparam table tag_names an array of tag names (strings)
-- @tparam string|nil tags_cond either "or", "and". `nil` means "or"
-- @treturn table|nil returns a table with entity_ids as values, and `true` as keys
local function get_entity_ids_tagged(key, tag_names, tags_cond)
  local cache = kong.core_cache
  local tag_name, list, err
  local dict = {} -- keys are entity_ids, values are true

  for i = 1, #tag_names do
    tag_name = tag_names[i]
    list, err = cache:get("taggings:" .. tag_name .. "|" .. key, nil, empty_list_cb)
    if not list then
      return nil, err
    end

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

  local cache = kong.core_cache
  if not cache then
    return {}
  end

  local list, err
  if options and options.tags then
    list, err = get_entity_ids_tagged(key, options.tags, options.tags_cond)
  else
    list, err = cache:get(key, nil, empty_list_cb)
  end

  if not list then
    return nil, err
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

    -- Tags are stored "tags|list" and "tags:<tagname>|list" as strings,
    -- encoded like "admin|services|<a service uuid>"
    -- We decode them into lua tables here
    if schema_name == "tags" then
      local tag_name, entity_name, uuid = string.match(item, "^([^|]+)|([^|]+)|(.+)$")
      if not tag_name then
        return nil, "Could not parse tag from cache: " .. tostring(item)
      end

      item = { tag = tag_name, entity_name = entity_name, entity_id = uuid }

    -- The rest of entities' lists (i.e. "services|list") only contain ids, so in order to
    -- get the entities we must do an additional cache access per entry
    else
      item = cache:get(schema_name .. ":" .. item .. "::::", nil, nil_cb)
    end

    ret[i - offset + 1] = item
  end

  if offset then
    return ret, nil, encode_base64(tostring(offset + size), true)
  end

  return ret
end


local function select_by_key(self, key)
  if not kong.core_cache then
    return nil
  end

  return kong.core_cache:get(key, nil, nil_cb)
end


local function page(self, size, offset, options)
  local key = self.schema.name .. "|list"
  return page_for_key(self, key, size, offset, options)
end


local function select(self, pk)
  local id = declarative_config.pk_string(self.schema, pk)
  local key = self.schema.name .. ":" .. id .. "::::"
  return select_by_key(self, key)
end


local function select_by_field(self, field, value)
  if type(value) == "table" then
    local _
    _, value = next(value)
  end

  local key = self.schema.name .. "|" .. field .. ":" .. value
  return select_by_key(self, key)
end


function off.new(connector, schema, errors)
  local unsupported = function(operation)
    local err = fmt("cannot %s '%s' entities when not using a database",
                    operation, schema.name)
    return function()
      return nil, errors:operation_unsupported(err)
    end
  end

  local unsupported_by = function(operation)
    local err = fmt("cannot %s '%s' entities by '%s' when not using a database",
                    operation, schema.name, '%s')
    return function(_, field_name)
      return nil, errors:operation_unsupported(fmt(err, field_name))
    end
  end

  local self = {
    connector = connector, -- instance of kong.db.strategies.off.connector
    schema = schema,
    errors = errors,
    page = page,
    select = select,
    select_by_field = select_by_field,

    insert = unsupported("create"),
    update = unsupported("update"),
    upsert = unsupported("create or update"),
    delete = unsupported("remove"),
    update_by_field = unsupported_by("update"),
    upsert_by_field = unsupported_by("create or update"),
    delete_by_field = unsupported_by("remove"),

    truncate = function() return true end,

    -- off-strategy specific methods:
    page_for_key = page_for_key,
  }

  local name = self.schema.name
  for fname, fdata in schema:each_field() do
    if fdata.type == "foreign" then
      local entity = fdata.reference
      local method = "page_for_" .. fname
      self[method] = function(_, foreign_key, size, offset, options)
        local key = name .. "|" .. entity .. "|" .. foreign_key.id .. "|list"
        return page_for_key(self, key, size, offset, options)
      end
    end
  end

  return setmetatable(self, _mt)
end


return off
