local _M = {}

local constants = require("cassandra.constants")

local function create_buffer(str)
  return {str=str, pos=1}
end
_M.create_buffer = create_buffer

local function read_raw(value)
  return value
end

local function string_to_number(str, signed)
  local number = 0
  local exponent = 1
  for i = #str, 1, -1 do
    number = number + string.byte(str, i) * exponent
    exponent = exponent * 256
  end
  if signed and number > exponent / 2 then
    -- 2's complement
    number = number - exponent
  end
  return number
end

local function read_signed_number(bytes)
  return string_to_number(bytes, true)
end

local function read_raw_bytes(buffer, n_bytes)
  local bytes = string.sub(buffer.str, buffer.pos, buffer.pos + n_bytes - 1)
  buffer.pos = buffer.pos + n_bytes
  return bytes
end
_M.read_raw_bytes = read_raw_bytes

local function read_raw_byte(buffer)
  return string.byte(read_raw_bytes(buffer, 1))
end
_M.read_raw_byte = read_raw_byte

local function read_int(buffer)
  return string_to_number(read_raw_bytes(buffer, 4), true)
end
_M.read_int = read_int

local function read_short(buffer)
  return string_to_number(read_raw_bytes(buffer, 2), false)
end
_M.read_short = read_short

local function read_string(buffer)
  local str_size = read_short(buffer)
  return read_raw_bytes(buffer, str_size)
end
_M.read_string = read_string

local function read_bytes(buffer)
  local size = read_int(buffer, true)
  if size < 0 then
    return nil
  end
  return read_raw_bytes(buffer, size)
end
_M.read_bytes = read_bytes

local function read_short_bytes(buffer)
  local size = read_short(buffer)
  return read_raw_bytes(buffer, size)
end
_M.read_short_bytes = read_short_bytes

local function read_option(buffer)
  local type_id = read_short(buffer)
  local type_value = nil
  if type_id == constants.types.custom then
    type_value = read_string(buffer)
  elseif type_id == constants.types.list then
    type_value = read_option(buffer)
  elseif type_id == constants.types.map then
    type_value = {read_option(buffer), read_option(buffer)}
  elseif type_id == constants.types.set then
    type_value = read_option(buffer)
  end
  return {id=type_id, value=type_value}
end
_M.read_option = read_option

local function read_boolean(bytes)
  return string.byte(bytes) == 1
end

local function read_bigint(bytes)
  local b1, b2, b3, b4, b5, b6, b7, b8 = string.byte(bytes, 1, 8)
  if b1 < 0x80 then
    return ((((((b1 * 0x100 + b2) * 0x100 + b3) * 0x100 + b4) * 0x100 + b5) * 0x100 + b6) * 0x100 + b7) * 0x100 + b8
  else
    return ((((((((b1 - 0xFF) * 0x100 + (b2 - 0xFF)) * 0x100 + (b3 - 0xFF)) * 0x100 + (b4 - 0xFF)) * 0x100 + (b5 - 0xFF)) * 0x100 + (b6 - 0xFF)) * 0x100 + (b7 - 0xFF)) * 0x100 + (b8 - 0xFF)) - 1
  end
end

local function read_double(bytes)
  local b1, b2, b3, b4, b5, b6, b7, b8 = string.byte(bytes, 1, 8)
  local sign = b1 > 0x7F
  local exponent = (b1 % 0x80) * 0x10 + math.floor(b2 / 0x10)
  local mantissa = ((((((b2 % 0x10) * 0x100 + b3) * 0x100 + b4) * 0x100 + b5) * 0x100 + b6) * 0x100 + b7) * 0x100 + b8
  if sign then
    sign = -1
  else
    sign = 1
  end
  local number
  if mantissa == 0 and exponent == 0 then
    number = sign * 0.0
  elseif exponent == 0x7FF then
    if mantissa == 0 then
      number = sign * math.huge
    else
      number = 0.0/0.0
    end
  else
    number = sign * math.ldexp(1.0 + mantissa / 0x10000000000000, exponent - 0x3FF)
  end
  return number
end

local function read_float(bytes)
  local b1, b2, b3, b4 = string.byte(bytes, 1, 4)
  local exponent = (b1 % 0x80) * 0x02 + math.floor(b2 / 0x80)
  local mantissa = math.ldexp(((b2 % 0x80) * 0x100 + b3) * 0x100 + b4, -23)
  if exponent == 0xFF then
    if mantissa > 0 then
      return 0 / 0
    else
      mantissa = math.huge
      exponent = 0x7F
    end
  elseif exponent > 0 then
    mantissa = mantissa + 1
  else
    exponent = exponent + 1
  end
  if b1 >= 0x80 then
    mantissa = -mantissa
  end
  return math.ldexp(mantissa, exponent - 0x7F)
end

local function read_uuid(bytes)
  local buffer = {}
  for i = 1, #bytes do
    buffer[i] = string.format("%02x", string.byte(bytes, i))
  end
  table.insert(buffer, 5, "-")
  table.insert(buffer, 8, "-")
  table.insert(buffer, 11, "-")
  table.insert(buffer, 14, "-")
  return table.concat(buffer)
end
_M.read_uuid = read_uuid

local function read_inet(bytes)
  local buffer = {}
  if #bytes == 16 then
    -- ipv6
    for i = 1, #bytes, 2 do
      buffer[#buffer + 1] = string.format("%02x", string.byte(bytes, i)) ..
                  string.format("%02x", string.byte(bytes, i + 1))
    end
    return table.concat(buffer, ":")
  end
  for i = 1, #bytes do
    buffer[#buffer + 1] = string.format("%d", string.byte(bytes, i))
  end
  return table.concat(buffer, ".")
end

local function read_list(bytes, type)
  local element_type = type.value
  local buffer = create_buffer(bytes)
  local n = read_short(buffer)
  local elements = {}
  for i = 1, n do
    elements[#elements + 1] = _M.read_value(buffer, element_type, true)
  end
  return elements
end

local read_set = read_list

local function read_map(bytes, type)
  local key_type = type.value[1]
  local value_type = type.value[2]
  local buffer = create_buffer(bytes)
  local n = read_short(buffer)
  local map = {}
  for i = 1, n do
    local key = _M.read_value(buffer, key_type, true)
    local value = _M.read_value(buffer, value_type, true)
    map[key] = value
  end
  return map
end

local decoders = {
  -- custom=0x00,
  [constants.types.ascii]=read_raw,
  [constants.types.bigint]=read_bigint,
  [constants.types.blob]=read_raw,
  [constants.types.boolean]=read_boolean,
  [constants.types.counter]=read_bigint,
  -- decimal=0x06,
  [constants.types.double]=read_double,
  [constants.types.float]=read_float,
  [constants.types.int]=read_signed_number,
  [constants.types.text]=read_raw,
  [constants.types.timestamp]=read_bigint,
  [constants.types.uuid]=read_uuid,
  [constants.types.varchar]=read_raw,
  [constants.types.varint]=read_signed_number,
  [constants.types.timeuuid]=read_uuid,
  [constants.types.inet]=read_inet,
  [constants.types.list]=read_list,
  [constants.types.map]=read_map,
  [constants.types.set]=read_set
}

local function read_value(buffer, type, short)
  local bytes
  if short then
    bytes = read_short_bytes(buffer)
  else
    bytes = read_bytes(buffer)
  end
  if bytes == nil then
    return nil
  end
  return decoders[type.id](bytes, type)
end
_M.read_value = read_value

return _M
