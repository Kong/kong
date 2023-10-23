local protojson = {
  _DESCRIPTION = [[
    Conversion between protobuf binary format and tables representing JSON
    
    Implementations used as a base:
      https://developers.google.com/protocol-buffers/docs/proto3#json
      https://pkg.go.dev/google.golang.org/protobuf/encoding/protojson
      https://github.com/protocolbuffers/protobuf/blob/master/python/google/protobuf/json_format.py
      https://github.com/protocolbuffers/protobuf/blob/master/src/google/protobuf/util/json_util.h
  ]]
}

local pb = require "pb"
local date = require "date"
local empty_array = require "cjson".empty_array
local ngx = ngx
local re_match = ngx.re.match
local re_gmatch = ngx.re.gmatch

local json_names = {}
local use_proto_names = false -- Emit proto field name instead of lowerCamelCase name. Read both formats.
local enum_as_name = true -- Emit enum values as strings instead of integers. Read both formats.
local emit_defaults = false -- Emit fields with default values.

--[[ HELPERS ]]------------------------------------------------

local function snake_to_camel_case(s)
  return s:gsub( "_(%l)", s.upper )
end

local function camel_to_snake_case(s)
  return (s:gsub( "(%u)", function(c) return "_" .. c:lower() end ))
end

local function get_json_name( type_name, field_name )
  local n = type_name .. "." .. field_name

  return json_names[ n ] or snake_to_camel_case( field_name )
end

-- modeled after https://chromium.googlesource.com/external/github.com/google/protobuf/+/HEAD/python/google/protobuf/json_format.py#389
local function type_url_to_type_name( type_url )
  local type_name, _ = re_match( type_url, "/([^/]+)$")
  --TODO: check pb.type( type_name ) for type validity

  return "." .. type_name[1]
end

local is_int = { 
  int64 = true, sint64 = true, sfixed64 = true, uint64 = true, fixed64 = true,
  int32 = true, sint32 = true, sfixed32 = true, uint32 = true, fixed32 = true
}

local is_int64 = {
  int64 = true, sint64 = true, sfixed64 = true, uint64 = true, fixed64 = true
}

local is_decimal = {
  float = true, double = true
}

local is_signed = {
  int32 = true, sint32 = true, sfixed32 = true,
  int64 = true, sint64 = true, sfixed64 = true
}

local is_wrapper = {
  [".google.protobuf.DoubleValue"] = true,
  [".google.protobuf.FloatValue"] = true,
  [".google.protobuf.Int64Value"] = true,
  [".google.protobuf.UInt64Value"] = true,
  [".google.protobuf.Int32Value"] = true,
  [".google.protobuf.UInt32Value"] = true,
  [".google.protobuf.BoolValue"] = true,
  [".google.protobuf.StringValue"] = true,
  [".google.protobuf.BytesValue"] = true,
}

local wrapper_default = {
  [".google.protobuf.DoubleValue"] = 0,
  [".google.protobuf.FloatValue"] = 0,
  [".google.protobuf.Int64Value"] = 0,
  [".google.protobuf.UInt64Value"] = 0,
  [".google.protobuf.Int32Value"] = 0,
  [".google.protobuf.UInt32Value"] = 0,
  [".google.protobuf.BoolValue"] = false,
  [".google.protobuf.StringValue"] = "",
  [".google.protobuf.BytesValue"] = "",
}

--[[ PROTO -> JSON helpers ]]------------------------------------------------------------------------
local message_to_json
local field_to_json = {}
local struct_msg_to_json = {}
local list_msg_to_json = {}
local value_msg_to_json = {}

local message_to_json_hooks = {
  [".google.protobuf.FieldMask"] = function (v)
    for k, p in ipairs( v.paths or {} ) do
      -- Changes to genuine google implementation:
      -- no validation
      -- both cases are accepted on input
      -- `use_proto_names` is respected
      if not use_proto_names then
        v.paths[k] = snake_to_camel_case(p)
      else
        v.paths[k] = camel_to_snake_case(p)
      end
    end

    return table.concat( v.paths, "," )
  end,

  [".google.protobuf.Any"] = function (v, p)
    -- https://developers.google.com/protocol-buffers/docs/reference/google.protobuf#any
    -- https://developers.google.com/protocol-buffers/docs/proto3#json
    -- https://chromium.googlesource.com/external/github.com/google/protobuf/+/HEAD/python/google/protobuf/json_format.py#596

    local t = type_url_to_type_name( v.type_url )
    local m = protojson:decode_to_json( t, v.value, p )

    m["@type"] = v.type_url

    return m
  end,

  [".google.protobuf.Timestamp"] = function (v, p)
    -- https://developers.google.com/protocol-buffers/docs/proto3#json
    if type(v) ~= "table" then
      error( ("expected table, got %q of type %s at %s"):format( tostring(v), type(v), p ), 0 )
    end

    local seconds = v.seconds or 0
    local nanos = v.nanos or 0

    local res = date( seconds + nanos * 1e-9 ):fmt("%Y-%m-%dT%H:%M:%\f")
    -- remove trailing zeroes as in https://github.com/golang/protobuf/blob/v1.5.2/jsonpb/encode.go#L204
    res = res:gsub("000$", "" )
    res = res:gsub("000$", "" )
    res = res:gsub(".000$", "" )

    return res .. "Z"
  end,

  [".google.protobuf.Duration"] = function (v, p)
    -- https://developers.google.com/protocol-buffers/docs/reference/google.protobuf#duration

    local seconds = v.seconds or 0
    local nanos = v.nanos or 0

    if ( seconds * nanos < 0 ) then
      error( ("seconds: %d and nanos: %d have different signs at %s"):format( seconds, nanos, p ), 0 )
    end

    return tostring( seconds + nanos * 1e-9 ) .. "s"
  end,

  [".google.protobuf.Struct"] = function (v, p)
    return struct_msg_to_json( v, p )
  end,

  [".google.protobuf.ListValue"] = function (v, p)
    return list_msg_to_json( v, p )
  end,

  [".google.protobuf.Value"] = function (v, p)
    return value_msg_to_json( v, p )
  end,
}

--- Transforms output from `pb.decode()` to input for `cjson.encode()`
-- @param m table representing protobuf message
-- @param m_type protobuf type of transformed message.
-- @param path for error localisation [optional]
message_to_json = function( m, m_type, path )
  path = path or "" -- path param is optional

  if message_to_json_hooks[ m_type ] ~= nil then   -- call hooks if available
    return message_to_json_hooks[ m_type ]( m, path )

  elseif is_wrapper[ m_type ] then
    local _, _, v_type = pb.field( m_type, "value" )
    -- wrapper default fixes pb.decode bug https://github.com/starwing/lua-protobuf/issues/194
    return field_to_json( m.value or wrapper_default[m_type], v_type, path )
  end

  local jm = {}

  for f_name, _, f_type, _, f_label in pb.fields( m_type ) do
    local _, _ , f_kind = pb.type( f_type ) -- get "map" | "enum" | "message"

    local name = f_name

    if not use_proto_names then
      name = get_json_name( m_type, f_name ) -- get json name from descriptor
    end

    if ( m[ f_name ] ~= nil ) then
      local p = path.."."..name

      if ( f_kind == "map" ) then
        local _, _, k_type = pb.field( f_type, "key" )
        local _, _, v_type = pb.field( f_type, "value" )

        jm[ name ] = {}

        for k, v in pairs( m[ f_name ] or {} ) do
          k = field_to_json( k, k_type, p..".key" )

          jm[ name ][ k ] = field_to_json( v, v_type, p..".value" )
        end
      elseif ( f_label == "repeated" or f_label == "packed" ) then
        jm[ name ] = {}

        for _, v in ipairs( m[ f_name ] or {} ) do
          table.insert( jm[ name ], field_to_json( v, f_type, p ) )
        end

        -- explicitely set as empty array to not be encoded as empty object {}
        if ( #jm[ name ] == 0 ) then
          jm[ name ] = empty_array
        end
      else
        -- handle singular field
        jm[ name ] = field_to_json( m[ f_name ], f_type, p )
      end
    end
  end

  return jm
end

--- Transforms proto field to a value suitable for `cjson`
-- @param f Table representing protobuf field.
-- @param f_type Protobuf type of transformed field.
-- @param path For error localisation [optional]
field_to_json = function( f, f_type, path )
  local _, _ , f_kind = pb.type( f_type ); -- get "map" | "enum" | "message"

  if ( f_kind == "message" ) then
    return message_to_json( f, f_type, path )
  elseif ( f_type == "bytes" ) then
    return ngx.encode_base64( f ) 
  elseif ( is_int[ f_type ] ) then -- parse numeric value
    if ( type(f) ~= "number" or f ~= f or f ~= math.floor( f ) ) then -- possibly remove
      error( ("invalid integer value at %s, got: %s"):format(path, f), 0 )
    end

    if is_int64[ f_type ] then
      return tostring( f )
    else
      return f
    end
  elseif ( is_decimal[ f_type ] ) then
    if f == math.huge then
      return "Inf"
    elseif f == -math.huge then
      return "-Inf"
    elseif f ~= f then
      return "NaN"
    end
  end
  -- enums and bools are handled by pb.decode

  return f
end

-- https://developers.google.com/protocol-buffers/docs/reference/google.protobuf#struct
-- https://github.com/protocolbuffers/protobuf/blob/master/python/google/protobuf/json_format.py#L367
struct_msg_to_json = function( v, path )
  local struct = {}

  for k, item in pairs(v.fields or {}) do
    struct[k] = value_msg_to_json( item, path.."."..k )
  end

  return struct
end

-- https://developers.google.com/protocol-buffers/docs/reference/google.protobuf#listvalue
-- https://github.com/protocolbuffers/protobuf/blob/master/python/google/protobuf/json_format.py#L362
list_msg_to_json = function( v, path )
  local list = {}

  for i, item in ipairs(v.values or {}) do
    table.insert( list, value_msg_to_json( item, path.."."..i ) )
  end

  return list
end

value_msg_to_json = function( v, path )
  local value = false

  for f_name, _, f_type in pb.fields( ".google.protobuf.Value" ) do
    if v[ f_name ] ~= nil then
      if ( value ) then
        error( ("oneof with multiple concurrent values at: %s"):format( path ), 0 )
      end

      if f_name == "struct_value" then
        value = struct_msg_to_json( v.struct_value, path.."."..f_name )
      elseif f_name == "list_value" then
        value = list_msg_to_json( v.list_value, path.."."..f_name )
      else
        value = v[ f_name ]
      end
    end
  end

  return value
end

--[[ JSON -> PROTO helpers ]]------------------------------------------------------------------------
local json_to_message
local json_to_field = {}
local json_to_struct_msg = {}
local json_to_list_msg = {}
local json_to_value_msg = {}

local json_to_message_hooks = {
  [".google.protobuf.FieldMask"] = function (v)
    local p = {}
    for m in re_gmatch( ( v.."," ), "(.+?)," ) do
      table.insert( p, camel_to_snake_case(m[1]) )
    end

    return { paths = p }
  end,

  [".google.protobuf.Any"] = function (v, p)
    -- https://developers.google.com/protocol-buffers/docs/proto3#json
    -- https://chromium.googlesource.com/external/github.com/google/protobuf/+/HEAD/python/google/protobuf/json_format.py#315

    if ( v["@type"] == nil ) then
      error( ("@type is missing when parsing any message at %s"):format( p ), 0 )
    end

    local t = type_url_to_type_name( v["@type"] )
    local m = { type_url = v["@type"] }

    m["value"] = protojson:encode_from_json( t, v, p )

    return m
  end,

  [".google.protobuf.Timestamp"] = function (v, p) -- https://developers.google.com/protocol-buffers/docs/proto3#json
    if type(v) ~= "string" then
      error( ("expected time string, got %q of type %s at %s"):format( tostring(v), type(v), p ), 0 )
    end
    local ds = date(v) - date.epoch()
    return {
      seconds = ds:spanseconds(),
      nanos = ds:getticks() * 1000,
    }
  end,

  [".google.protobuf.Duration"] = function (v, p)
    -- https://developers.google.com/protocol-buffers/docs/reference/google.protobuf#duration

    local patt_nanos = "^(-?)(%d+)%.(%d+)s$"
    local patt_seconds = "^(-?)(%d+)s$"

    if v:find( patt_nanos ) then
      return {
        seconds = tonumber(( v:gsub( patt_nanos, "%1%2" ) )),
        nanos = tonumber(( v:gsub( patt_nanos, "%10.%3" ) )) * 1e9,
      }
    elseif v:find( patt_seconds ) then
      return {
        seconds = tonumber(( v:gsub( patt_seconds, "%1%2" ) )),
        nanos = 0
      }
    else
      error( ("duration: %s should be in format `seconds[.nanos]s` at %s"):format(v, p), 0 )
    end
  end,

  [".google.protobuf.Struct"] = function (v, p)
    return json_to_struct_msg( v, p )
  end,

  [".google.protobuf.ListValue"] = function (v, p)
    return json_to_list_msg( v, p )
  end,

  [".google.protobuf.Value"] = function (v, p)
    return json_to_value_msg( v, p )
  end,
}

--- Transforms `cjson.decode()` table to input for pb.encode().
-- @param m Table representing message
-- @param m_type Protobuf type of transformed message.
-- @param path For error localisation [optional]
json_to_message = function( m, m_type, path )
  path = path or "" -- path param is optional

  if json_to_message_hooks[ m_type ] ~= nil then -- call hooks if available
    return json_to_message_hooks[ m_type ]( m, path )

  elseif is_wrapper[ m_type ] then
    local _, _, v_type = pb.field( m_type, "value" )
    return { value = json_to_field( m, v_type, path..".value" ) }
  end

  local pm = {}

  for f_name, _, f_type, _, f_label in pb.fields( m_type ) do
    local name = get_json_name( m_type, f_name ) -- get json name from descriptor

    -- if there is no camelCase name, try name from descriptor
    if ( m[ name ] == nil ) then
      name = f_name
    end

    if ( m[ name ] ~= nil ) then -- do only if the value is provided
      local p = path.."."..name
      local _, _ , f_kind = pb.type( f_type ) -- get "map" | "enum" | "message"

      if ( f_kind == "map" ) then
        local _, _, k_type = pb.field( f_type, "key" )
        local _, _, v_type = pb.field( f_type, "value" )

        pm[ f_name ] = {}

        for k, v in pairs( m[ name ] or {} ) do
          k = json_to_field( k, k_type, p..".key" )

          pm[ f_name ][ k ] = json_to_field( v, v_type, p..".value" )
        end
      elseif ( f_label == "repeated" or f_label == "packed" ) then
        pm[ f_name ] = {}

        -- if the input is just a scalar - might happen for single-value table
        if ( type( m[ name ] ) == "string" or type( m[ name ] ) == "number" )  then
          m[ name ] = { m[ name ] } -- convert to a table
        end

        for k, v in ipairs( m[ name ] or {} ) do
          table.insert( pm[ f_name ], json_to_field( v, f_type, ( "%s[%d]" ):format( p, k ) ) )
        end
      else -- singular field
        pm[ f_name ] = json_to_field( m[ name ], f_type, p )
      end
    end
  end

  return pm
end

--- Transforms value from `cjson` to proto field
-- @param f table Representing value of protobuf field.
-- @param f_type Protobuf type of transformed field.
-- @param path For error localisation [optional]
json_to_field = function( f, f_type, path )
  local _, _ , f_kind = pb.type( f_type ); -- get "map" | "enum" | "message"

  if ( f_kind == "message" ) then
    return json_to_message( f, f_type, path )
  elseif ( f_type == "bytes" ) then
    local v = ngx.decode_base64( f )

    if ( v == nil ) then
      error( ("invalid base64 value at %s, got: %s"):format( path, f ), 0 )
    else
      return v
    end
  elseif ( f_kind == "enum" ) then
    if ( type( f ) == "number" ) then
      return json_to_field( f , "int32", path )
    else
      local v = pb.enum( f_type, f )

      if ( v == nil ) then
        error( ("invalid enumeration value at %s, got: %s"):format(path, f), 0 )
      else
        return v
      end
    end
  elseif ( f_type == "bool" ) then
    -- special case for URI parameters
    if ( f == "true" or f == "1" ) then f = true end
    if ( f == "false" or f == "0" ) then f = false end

    if ( type( f ) ~= "boolean" ) then
      error( ("expected boolean value at %s, got: '%s' of type: %s"):format(path, f, type(f)), 0 )
    end
  elseif ( is_int[ f_type ] ) then -- parse numeric value
    if ( tonumber( f ) == nil ) then
      error( ("invalid numeric value at %s, got: '%s'"):format(path, f), 0 )
    end

    f = tonumber( f )

    if ( f < 0 and not is_signed[ f_type ] ) then
      error( ("unsigned value required at %s, got %d"):format(path, f), 0 )
    elseif ( f ~= math.floor( f ) ) then
      error( ("integer value required at %s, got %f"):format(path, f), 0 )
    end
  elseif ( is_decimal[ f_type ] ) then
    if ( tonumber( f ) == nil ) then
      error( ("invalid numeric value at %s, got: %s"):format(path, f), 0 )
    end

    f = tonumber( f )
  end

  return f
end

-- https://developers.google.com/protocol-buffers/docs/reference/google.protobuf#struct
-- https://github.com/protocolbuffers/protobuf/blob/master/python/google/protobuf/json_format.py#L703
json_to_struct_msg = function( v )
  local struct = { fields = {} }

  for k, item in pairs(v or {}) do
    struct.fields[ tostring( k ) ] = json_to_value_msg( item )
  end

  return struct
end

-- https://developers.google.com/protocol-buffers/docs/reference/google.protobuf#listvalue
-- https://github.com/protocolbuffers/protobuf/blob/master/python/google/protobuf/json_format.py#L693
json_to_list_msg = function( v )
  local list = { values = {} }

  for _, item in ipairs(v or {}) do
    table.insert( list.values, json_to_value_msg( item ) )
  end

  return list
end

-- https://developers.google.com/protocol-buffers/docs/reference/google.protobuf#value
-- https://github.com/protocolbuffers/protobuf/blob/master/python/google/protobuf/json_format.py#L675
json_to_value_msg = function( v )
  if type(v) == 'table' then
    local c = 0

    for _ in pairs(v) do c = c + 1 end

    if #v == c then -- type = list
      return { list_value = json_to_list_msg(v) }
    else -- type = struct
      return { struct_value = json_to_struct_msg(v) }
    end
  elseif type(v) == 'boolean' then
    return { bool_value = v }
  elseif type(v) == 'number' then
    return { number_value = v }
  elseif type(v) == 'string' then
    return { string_value = v }
  else
    return { null_value = 0 }
  end
end

--[[ API ]]------------------------------------------------------------------------

--- Encodes output of `cjson.encode()` into bytestream
-- @param msg table Representing json protobuf message
-- @param msg_type Protobuf type of transformed message.
-- @param path For error localisation [optional]
function protojson:encode_from_json( msg_type, msg, path )
  return pb.encode( msg_type, json_to_message( msg, msg_type, path ) )
end

--- Decode bytestream to to input for `cjson.encode()`
-- @param msg Table representing json protobuf message
-- @param msg_type Protobuf type of transformed message.
-- @param path For error localisation [optional]
function protojson:decode_to_json( msg_type, msg, path )
  if ( emit_defaults ) then
    pb.option( "use_default_values" )
  else
    pb.option( "no_default_values" )
  end
  
  if ( enum_as_name ) then
    pb.option( "enum_as_name" )
  else
    pb.option( "enum_as_value" )
  end

  pb.option( "int64_as_number" )

  return message_to_json( pb.decode( msg_type, msg ), msg_type, path )
end

--- Decode bytestream to to input for `cjson.encode()`
-- @param options.use_proto_names_ Emit proto field name instead of lowerCamelCase name. Read both.
-- @param options.enum_as_name_ Emit enum values as integers instead of strings. Read both.
-- @param options.emit_defaults_ Emit fields with default values
-- @param options.json_names_ Table containing json_name options of parsed fields
function protojson:configure( options )
  use_proto_names = options.use_proto_names or false
  enum_as_name = options.enum_as_name or false
  emit_defaults = options.emit_defaults or false
  json_names = options.json_names or {}
end

return protojson
