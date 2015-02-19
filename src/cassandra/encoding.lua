local constants = require("cassandra.constants")

local _M = {}

local function big_endian_representation(num, bytes)
  if num < 0 then
    -- 2's complement
    num = math.pow(0x100, bytes) + num
  end
  local t = {}
  while num > 0 do
    local rest = math.fmod(num, 0x100)
    table.insert(t, 1, string.char(rest))
    num = (num-rest) / 0x100
  end
  local padding = string.rep(string.char(0), bytes - #t)
  return padding .. table.concat(t)
end

local function int_representation(num)
  return big_endian_representation(num, 4)
end
_M.int_representation = int_representation

local function short_representation(num)
  return big_endian_representation(num, 2)
end
_M.short_representation = short_representation

local function bigint_representation(n)
  local first_byte
  if n >= 0 then
    first_byte = 0
  else
    first_byte = 0xFF
  end
  return string.char(first_byte, -- only 53 bits from double
                     math.floor(n / 0x1000000000000) % 0x100,
                     math.floor(n / 0x10000000000) % 0x100,
                     math.floor(n / 0x100000000) % 0x100,
                     math.floor(n / 0x1000000) % 0x100,
                     math.floor(n / 0x10000) % 0x100,
                     math.floor(n / 0x100) % 0x100,
                     n % 0x100)
end

local function uuid_representation(value)
  local str = string.gsub(value, "-", "")
  local buffer = {}
  for i = 1, #str, 2 do
    local byte_str =  string.sub(str, i, i + 1)
    buffer[#buffer + 1] = string.char(tonumber(byte_str, 16))
  end
  return table.concat(buffer)
end

local function string_representation(str)
  return short_representation(#str) .. str
end
_M.string_representation = string_representation

local function long_string_representation(str)
  return int_representation(#str) .. str
end
_M.long_string_representation = long_string_representation

local function bytes_representation(bytes)
  return int_representation(#bytes) .. bytes
end
_M.bytes_representation = bytes_representation

local function short_bytes_representation(bytes)
  return short_representation(#bytes) .. bytes
end
_M.short_bytes_representation = short_bytes_representation

local function string_map_representation(map)
  local buffer = {}
  local n = 0
  for k, v in pairs(map) do
    buffer[#buffer + 1] = string_representation(k)
    buffer[#buffer + 1] = string_representation(v)
    n = n + 1
  end
  return short_representation(n) .. table.concat(buffer)
end
_M.string_map_representation = string_map_representation

local function boolean_representation(value)
  if value then return "\001" else return "\000" end
end
_M.boolean_representation = boolean_representation

-- 'inspired' by https://github.com/fperrad/lua-MessagePack/blob/master/src/MessagePack.lua
local function double_representation(number)
  local sign = 0
  if number < 0.0 then
    sign = 0x80
    number = -number
  end
  local mantissa, exponent = math.frexp(number)
  if mantissa ~= mantissa then
    return string.char(0xFF, 0xF8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00) -- nan
  elseif mantissa == math.huge then
    if sign == 0 then
      return string.char(0x7F, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00) -- +inf
    else
      return string.char(0xFF, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00) -- -inf
    end
  elseif mantissa == 0.0 and exponent == 0 then
    return string.char(sign, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00) -- zero
  else
    exponent = exponent + 0x3FE
    mantissa = (mantissa * 2.0 - 1.0) * math.ldexp(0.5, 53)
    return string.char(sign + math.floor(exponent / 0x10),
        (exponent % 0x10) * 0x10 + math.floor(mantissa / 0x1000000000000),
        math.floor(mantissa / 0x10000000000) % 0x100,
        math.floor(mantissa / 0x100000000) % 0x100,
        math.floor(mantissa / 0x1000000) % 0x100,
        math.floor(mantissa / 0x10000) % 0x100,
        math.floor(mantissa / 0x100) % 0x100,
        mantissa % 0x100)
  end
end

local function float_representation(number)
  if number == 0 then
    return string.char(0x00, 0x00, 0x00, 0x00)
  elseif number ~= number then
    return string.char(0xFF, 0xFF, 0xFF, 0xFF)
  else
    local sign = 0x00
    if number < 0 then
      sign = 0x80
      number = -number
    end
    local mantissa, exponent = math.frexp(number)
    exponent = exponent + 0x7F
    if exponent <= 0 then
      mantissa = math.ldexp(mantissa, exponent - 1)
      exponent = 0
    elseif exponent > 0 then
      if exponent >= 0xFF then
        return string.char(sign + 0x7F, 0x80, 0x00, 0x00)
      elseif exponent == 1 then
        exponent = 0
      else
        mantissa = mantissa * 2 - 1
        exponent = exponent - 1
      end
    end
    mantissa = math.floor(math.ldexp(mantissa, 23) + 0.5)
    return string.char(
        sign + math.floor(exponent / 2),
        (exponent % 2) * 0x80 + math.floor(mantissa / 0x10000),
        math.floor(mantissa / 0x100) % 0x100,
        mantissa % 0x100)
  end
end

local function inet_representation(value)
  local digits = {}
  -- ipv6
  for d in string.gmatch(value, "([^:]+)") do
    if #d == 4 then
      for i = 1, #d, 2 do
        digits[#digits + 1] = string.char(tonumber(string.sub(d, i, i + 1), 16))
      end
    end
  end
  -- ipv4
  if #digits == 0 then
    for d in string.gmatch(value, "(%d+)") do
      table.insert(digits, string.char(d))
    end
  end
  return table.concat(digits)
end

local function list_representation(elements)
  local buffer = {short_representation(#elements)}
  for _, value in ipairs(elements) do
    buffer[#buffer + 1] = _M._value_representation(value, true)
  end
  return table.concat(buffer)
end

local function set_representation(elements)
  return list_representation(elements)
end

local function map_representation(map)
  local buffer = {}
  local size = 0
  for key, value in pairs(map) do
    buffer[#buffer + 1] = _M._value_representation(key, true)
    buffer[#buffer + 1] = _M._value_representation(value, true)
    size = size + 1
  end
  table.insert(buffer, 1, short_representation(size))
  return table.concat(buffer)
end

local function identity_representation(value)
  return value
end

local encoders = {
  -- custom=0x00,
  [constants.types.ascii]=identity_representation,
  [constants.types.bigint]=bigint_representation,
  [constants.types.blob]=identity_representation,
  [constants.types.boolean]=boolean_representation,
  [constants.types.counter]=bigint_representation,
  -- decimal=0x06,
  [constants.types.double]=double_representation,
  [constants.types.float]=float_representation,
  [constants.types.int]=int_representation,
  [constants.types.text]=identity_representation,
  [constants.types.timestamp]=bigint_representation,
  [constants.types.uuid]=uuid_representation,
  [constants.types.varchar]=identity_representation,
  [constants.types.varint]=int_representation,
  [constants.types.timeuuid]=uuid_representation,
  [constants.types.inet]=inet_representation,
  [constants.types.list]=list_representation,
  [constants.types.map]=map_representation,
  [constants.types.set]=set_representation
}

local function infer_type(value)
  if type(value) == 'number' and math.floor(value) == value then
    return constants.types.int
  elseif type(value) == 'number' then
    return constants.types.float
  elseif type(value) == 'boolean' then
    return constants.types.boolean
  elseif type(value) == 'table' and value.type == 'null' then
    return _M.null
  elseif type(value) == 'table' and value.type then
    return constants.types[value.type]
  else
    return constants.types.varchar
  end
end

local function value_representation(value, short)
  local infered_type = infer_type(value)
  if type(value) == 'table' and value.type and value.value then
    value = value.value
  end
  if infered_type == _M.null then
    if short then
      return short_representation(-1)
    else
      return int_representation(-1)
    end
  end
  local representation = encoders[infered_type](value)
  if short then
    return short_bytes_representation(representation)
  end
  return bytes_representation(representation)
end
_M._value_representation = value_representation

local function values_representation(args)
  if not args then
    return ""
  end
  local values = {}
  values[#values + 1] = short_representation(#args)
  for _, value in ipairs(args) do
    values[#values + 1] = value_representation(value)
  end
  return table.concat(values)
end
_M.values_representation = values_representation

function _M.batch_representation(queries, batch_type)
  local b = {}
  -- <type>
  b[#b + 1] = string.char(batch_type)
  -- <n> (number of queries)
  b[#b + 1] = short_representation(#queries)
  -- <query_i> (operations)
  for _, query in ipairs(queries) do
    local kind
    local string_or_id
    if type(query.query) == "string" then
      kind = boolean_representation(false)
      string_or_id = long_string_representation(query.query)
    else
      kind = boolean_representation(true)
      string_or_id = short_bytes_representation(query.query.id)
    end

    -- The behaviour is sligthly different than from <query_parameters>
    -- for <query_parameters>:
    --   [<n><value_1>...<value_n>] (n cannot be 0), otherwise is being mixed up with page_size
    -- for batch <query_i>:
    --   <kind><string_or_id><n><value_1>...<value_n> (n can be 0, but is required)
    if query.args then
      b[#b + 1] = kind .. string_or_id .. values_representation(query.args)
    else
      b[#b + 1] = kind .. string_or_id .. short_representation(0)
    end
  end

  -- <type><n><query_1>...<query_n>
  return table.concat(b)
end

return _M
