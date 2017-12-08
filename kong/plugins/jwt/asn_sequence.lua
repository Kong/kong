local error = error
local string_sub = string.sub
local string_byte = string.byte
local string_char = string.char
local table_sort = table.sort
local table_insert = table.insert

local _M = {}
_M.__index = _M

function _M.create_simple_sequence(input)
  if type(input) ~= "table"
    then error("Argument #1 must be a table", 2)
  end
  local sortTable = {}
  for pair in pairs(input) do
    table_insert(sortTable, pair)
  end
  table_sort(sortTable)
  local numbers = ""
  for i,n in ipairs(sortTable) do
    if type(n) ~= "number"
      then error("Table must use numbers as keys", 2)
    end
    local number = input[sortTable[i]]
    if type(number) ~= "string" then
      error("Table contains non-string value.", 2)
    end
    local length = #number
    if length > 0x7F then
      error("Mult-byte lengths are not supported")
    end
    numbers = numbers .. "\x02" .. string_char(length) .. number
  end
  if #numbers > 0x7F
    then error("Multi-byte lengths are not supported")
  end
  return "\x30" .. string_char(#numbers) .. numbers
end

function _M.parse_simple_sequence(input)
  if type(input) ~= "string" then
    error("Argument #1 must be string", 2)
  elseif #input == 0 then
    error("Argument #1 must not be empty", 2)
  end
  if string_byte(input, 1) ~= 0x30 then
    error("Argument #1 is not a sequence")
  end
  local length = string_byte(input, 2)
  if length == nil then
    error("Sequence is incomplete")
  elseif length > 0x7F then
    error("Multi-byte lengths are not supported")
  elseif length ~= #input-2 then
    error("Sequence's asn length does not match expected length")
  end
  local seq = {}
  local counter = 1
  local position = 3
  while true do
    if position == #input+1 then
      break
    elseif position > #input+1 then
      error("Sequence moved out of bounds.")
    elseif counter > 0xFF then
      error("Sequence is too long")
    end
    local chunk = string_sub(input, position)
    if string_byte(chunk, 1) ~= 0x2 then
      error("Sequence did not contain integers")
    end
    local integerLength = string_byte(chunk, 2)
    if integerLength > 0x7F then
      error("Multi-byte lengths are not supported.")
    elseif integerLength > #chunk-2 then
      error("Integer is longer than remaining length")
    end
    local integer = string_sub(chunk, 3, integerLength+2)
    seq[counter] = integer
    position = position + integerLength + 2
    counter = counter + 1
  end
  return seq
end

function _M.unsign_integer(input, len)
  if type(input) ~= "string" then
    error("Argument #1 must be string", 2)
  elseif #input == 0 then
    error("Argument #1 must not be empty", 2)
  end
  if string_byte(input) ~= 0 and #input > len then
    error("Cannot unsign integer to length.", 2)
  elseif string_byte(input) == 0 and #input == len+1 then
    return string_sub(input, 2)
  end
  if #input == len then
    return input
  elseif #input < len then
    while #input < len do
      input = "\x00" .. input
    end
    return input
  else
    error("Unable to unsign integer")
  end
end

-- @param input (string) 32 characters, format to be validated before calling
function _M.resign_integer(input)
  if type(input) ~= "string" then
    error("Argument #1 must be string", 2)
  end
  if string_byte(input) > 0x7F then
    input = "\x00" .. input
  end
  while true do
    if string_byte(input) == 0 and string_byte(input, 2) <= 0x7F then
      input = string_sub(input, 2, -1)
    else
      break
    end
  end
  return input
end

return _M
