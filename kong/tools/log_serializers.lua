local basic_serializer = require "kong.plugins.log-serializers.basic"

local Serializers = {}

local chunks = {}

local function load_serializer_from_db(serializer)
  local row, err = kong.db.log_serializers:select(serializer)
  if err then
    return nil, err
  end

  if not row then
    return nil, "serializer '" .. tostring(serializer.id) .. "' not found"
  end

  return row.chunk
end

-- fetch the serializer from the DB via kong.cache
function Serializers.load_serializer(serializer)
  -- we werent passed a serializer object, so there's nothing to fetch
  if not serializer then
    ngx.log(ngx.DEBUG, "empty serializer, bailing")
    return true
  end

  -- already have it
  if chunks[serializer.id] then
    return true
  end

  local chunk, err = load_serializer_from_db(serializer)
  if err then
    return nil, err
  end

  local s = loadstring(ngx.decode_base64(chunk))
  if not s then
    return nil, "failed to load serializer chunk"
  end

  chunks[serializer.id] = s().serialize

  return true
end

-- return the serializer function from our cache
function Serializers.get_serializer(serializer)
  -- no serializer defined, use the default
  if not serializer then
    return basic_serializer.serialize
  end

  if not chunks[serializer.id] then
    return nil, "serializer '" .. serializer.id .. "' not found"
  end

  return chunks[serializer.id]
end

function Serializers.clear_serializer(serializer)
  chunks[serializer.id] = nil
end

return Serializers
