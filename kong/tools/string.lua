local pl_stringx = require "pl.stringx"


local type     = type
local ipairs   = ipairs
local tostring = tostring
local lower    = string.lower
local sub      = string.sub
local fmt      = string.format
local find     = string.find
local gsub     = string.gsub
local byte     = string.byte


local SPACE_BYTE = byte(" ")
local TAB_BYTE   = byte("\t")
local CR_BYTE    = byte("\r")


local _M = {}


_M.join = pl_stringx.join


--- splits a string.
-- just a placeholder to the penlight `pl.stringx.split` function
-- @function split
_M.split = pl_stringx.split


--- strips whitespace from a string.
-- @function strip
_M.strip = function(value)
  if value == nil then
    return ""
  end

  -- TODO: do we want to operate on non-string values (kept for backward compatibility)?
  if type(value) ~= "string" then
    value = tostring(value) or ""
  end

  if value == "" then
    return ""
  end

  local len = #value
  local s = 1 -- position of the leftmost non-whitespace char
  for i = 1, len do
    local b = byte(value, i)
    if b == SPACE_BYTE or (b >= TAB_BYTE and b <= CR_BYTE) then
      s = s + 1
    else
      break
    end
  end

  if s > len then
    return ""
  end

  local e = len -- position of the rightmost non-whitespace char
  if s < e then
    for i = e, 1, -1 do
      local b = byte(value, i)
      if b == SPACE_BYTE or (b >= TAB_BYTE and b <= CR_BYTE) then
        e = e - 1
      else
        break
      end
    end
  end

  if s ~= 1 or e ~= len then
    value = sub(value, s, e)
  end

  return value
end


-- Numbers taken from table 3-7 in www.unicode.org/versions/Unicode6.2.0/UnicodeStandard-6.2.pdf
-- find-based solution inspired by http://notebook.kulchenko.com/programming/fixing-malformed-utf8-in-lua
function _M.validate_utf8(val)
  local str = tostring(val)
  local i, len = 1, #str
  while i <= len do
    if     i == find(str, "[%z\1-\127]", i) then i = i + 1
    elseif i == find(str, "[\194-\223][\123-\191]", i) then i = i + 2
    elseif i == find(str,        "\224[\160-\191][\128-\191]", i)
        or i == find(str, "[\225-\236][\128-\191][\128-\191]", i)
        or i == find(str,        "\237[\128-\159][\128-\191]", i)
        or i == find(str, "[\238-\239][\128-\191][\128-\191]", i) then i = i + 3
    elseif i == find(str,        "\240[\144-\191][\128-\191][\128-\191]", i)
        or i == find(str, "[\241-\243][\128-\191][\128-\191][\128-\191]", i)
        or i == find(str,        "\244[\128-\143][\128-\191][\128-\191]", i) then i = i + 4
    else
      return false, i
    end
  end

  return true
end


---
-- Converts bytes to another unit in a human-readable string.
-- @tparam number bytes A value in bytes.
--
-- @tparam[opt] string unit The unit to convert the bytes into. Can be either
-- of `b/B`, `k/K`, `m/M`, or `g/G` for bytes (unchanged), kibibytes,
-- mebibytes, or gibibytes, respectively. Defaults to `b` (bytes).
-- @tparam[opt] number scale The number of digits to the right of the decimal
-- point. Defaults to 2.
-- @treturn string A human-readable string.
-- @usage
--
-- bytes_to_str(5497558) -- "5497558"
-- bytes_to_str(5497558, "m") -- "5.24 MiB"
-- bytes_to_str(5497558, "G", 3) -- "5.120 GiB"
--
function _M.bytes_to_str(bytes, unit, scale)
  local u = lower(unit or "")

  if u == "" or u == "b" then
    return fmt("%d", bytes)
  end

  scale = scale or 2

  if type(scale) ~= "number" or scale < 0 then
    error("scale must be equal or greater than 0", 2)
  end

  local fspec = fmt("%%.%df", scale)

  if u == "k" then
    return fmt(fspec .. " KiB", bytes / 2^10)
  end

  if u == "m" then
    return fmt(fspec .. " MiB", bytes / 2^20)
  end

  if u == "g" then
    return fmt(fspec .. " GiB", bytes / 2^30)
  end

  error("invalid unit '" .. unit .. "' (expected 'k/K', 'm/M', or 'g/G')", 2)
end


local SCALES = {
  k = 1024,
  K = 1024,
  m = 1024 * 1024,
  M = 1024 * 1024,
  g = 1024 * 1024 * 1024,
  G = 1024 * 1024 * 1024,
}

function _M.parse_ngx_size(str)
  assert(type(str) == "string", "Parameter #1 must be a string")

  local len = #str
  local unit = sub(str, len)
  local scale = SCALES[unit]

  if scale then
    len = len - 1

  else
    scale = 1
  end

  local size = tonumber(sub(str, 1, len)) or 0

  return size * scale
end


local try_decode_base64
do
  local decode_base64    = ngx.decode_base64
  local decode_base64url = require "ngx.base64".decode_base64url

  local function decode_base64_str(str)
    if type(str) == "string" then
      return decode_base64(str)
             or decode_base64url(str)
             or nil, "base64 decoding failed: invalid input"

    else
      return nil, "base64 decoding failed: not a string"
    end
  end

  function try_decode_base64(value)
    if type(value) == "table" then
      for i, v in ipairs(value) do
        value[i] = decode_base64_str(v) or v
      end

      return value
    end

    if type(value) == "string" then
      return decode_base64_str(value) or value
    end

    return value
  end
end
_M.try_decode_base64 = try_decode_base64


local replace_dashes
local replace_dashes_lower
do
  local str_replace_char

  if ngx and ngx.config.subsystem == "http" then

    -- 1,000,000 iterations with input of "my-header":
    -- string.gsub:        81ms
    -- ngx.re.gsub:        74ms
    -- loop/string.buffer: 28ms
    -- str_replace_char:   14ms
    str_replace_char = require("resty.core.utils").str_replace_char

  else    -- stream subsystem
    str_replace_char = function(str, ch, replace)
      if not find(str, ch, nil, true) then
        return str
      end

      return gsub(str, ch, replace)
    end
  end

  replace_dashes = function(str)
    return str_replace_char(str, "-", "_")
  end

  replace_dashes_lower = function(str)
    return str_replace_char(str:lower(), "-", "_")
  end
end
_M.replace_dashes = replace_dashes
_M.replace_dashes_lower = replace_dashes_lower


return _M
