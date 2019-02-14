local declarative_config = require("kong.db.schema.others.declarative_config")


local off = {}


local _mt = {}
_mt.__index = _mt


local function page_for_key(self, key, size, offset)
  offset = offset and tonumber(offset) or 1

  if not kong.cache then
    return {}
  end

  local list = kong.cache:get(key, nil, function()
    return {}
  end)
  if not list then
    return nil
  end

  local ret = {}
  local name = self.schema.name
  for i = 0, size - 1 do
    local id = list[i + offset]
    if not id then
      offset = nil
      break
    end

    local ck = name .. ":" .. id .. "::::"
    local entry = kong.cache:get(ck, nil, function()
      return nil
    end)
    table.insert(ret, entry)
  end

  if offset then
    return ret, nil, tostring(offset + size)
  end

  return ret
end


local function select_by_key(self, key)
  if not kong.cache then
    return nil
  end

  return kong.cache:get(key, nil, function()
    return nil
  end)
end


local function page(self, size, offset)
  local key = self.schema.name .. "|list"
  return page_for_key(self, key, size, offset)
end


local function select(self, pk)
  local id = declarative_config.pk_string(self.schema, pk)
  local key = self.schema.name .. ":" .. id .. "::::"
  return select_by_key(self, key)
end


local function select_by_field(self, field, value)
  local key = self.schema.name .. "|" .. field .. ":" .. value
  return select_by_key(self, key)
end


function off.new(connector, schema, errors)
  local unsupported = function(operation)
    local err = fmt("cannot %s '%s' entities when not using a database", operation, schema.name)
    return function()
      return nil, errors:operation_unsupported(err)
    end
  end

  local unsupported_by = function(operation)
    local err = fmt("cannot %s '%s' entities by '%s' when not using a database", operation, schema.name, '%s')
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
  }

  -- TODO implement page_for_* methods,

  local name = self.schema.name
  for fname, fdata in schema:each_field() do
    if fdata.type == "foreign" then
      local entity = fdata.reference
      local method = "page_for_" .. fname
      self[method] = function(_, foreign_key, size, offset)
        local key = name .. "|" .. entity .. "|" .. foreign_key.id .. "|list"
        return page_for_key(self, key, size, offset)
      end
    end
  end

  return setmetatable(self, _mt)
end


return off
