local new_tab = require "table.new"


local type     = type
local ipairs   = ipairs
local tostring = tostring
local lower    = string.lower
local sub      = string.sub
local fmt      = string.format
local find     = string.find
local gsub     = string.gsub
local byte     = string.byte
local char     = string.char
local huge     = math.huge


local SPACE_BYTE = byte(" ")
local TAB_BYTE   = byte("\t")
local CR_BYTE    = byte("\r")


local _M = {}


_M.join = require("pl.stringx").join


--- splits a string (kept for backward compatibility, use splitn instead).
-- just a placeholder to the penlight `pl.stringx.split` function
-- @function split
_M.split = require("pl.stringx").split


local function split_once_common(value, pattern, plain)
  if value == nil then
    return nil, nil
  elseif pattern == nil then
    return value, nil
  elseif pattern == "" then
    return "", value
  elseif value == "" then
    return "", nil
  end

  local s, e = find(value, pattern, nil, plain)
  if not s then
    return value, nil
  end

  if s == 1 and e == 1 then
    return "", (sub(value, e + 1))
  end

  return (sub(value, 1, s - 1)), (sub(value, e + 1))
end


--- splits a string once with a plain delimiter.
-- @function split_once
function _M.split_once(value, delim)
  local k, v = split_once_common(value, delim, true)
  return k, v
end


--- splits a string once with a pattern.
-- @function split_once
function _M.psplit_once(value, pattern)
  local k, v = split_once_common(value, pattern, false)
  return k, v
end


local function splitn_common(value, pattern, n, plain)
  local limit = n or huge
  if limit < 1 or value == nil then
    return {}, 0

  elseif limit == 1 or pattern == nil then
    return { value }, 1

  elseif pattern == "" then
    if value == "" then
      return { "", "" }, 2
    end

    local size = #value
    if size == 1 then
      if limit == 2 then
        return { "", value }, 2
      else
        return { "", value, "" }, 3
      end
    end

    size = limit >= size + 2 and size + 2 or limit

    local t
    if size > 100 then
      t = new_tab(size, 0)
      t[1] = ""
      for i = 2, size do
        t[i] = sub(value, i - 1, i < size and i - 1 or nil)
      end

    else
      t = { "", byte(value, 1, size - 2) }
      for i = 2, size do
        t[i] = t[i] and char(t[i]) or sub(value, i - 1)
      end
    end

    return t, size

  elseif value == "" then
    return { "" }, 1
  end

  local s, e = find(value, pattern, nil, plain)
  if not s then
    return { value }, 1
  end

  local t, i, p = new_tab(n or 10, 0), 1
  t[1] = sub(value, 1, s - 1)

  ::again::
  i, p = i + 1, e + 1
  if i < limit then
    s, e = find(value, pattern, p, plain)
    if s then
      t[i] = sub(value, p, s - 1)
      goto again
    end
  end
  t[i] = sub(value, p)
  return t, i
end


local function splitn(value, delim, n)
  value, n = splitn_common(value, delim, n, true)
  return value, n
end


local function psplitn(value, pattern, n)
  value, n = splitn_common(value, pattern, n, false)
  return value, n
end


--- splits a string with a plain delimiter (much faster than the split above).
-- @function splitn
_M.splitn = splitn


--- splits a string with a pattern.
-- @function psplitn
_M.psplitn = psplitn


local function noop_iter() end
local function once_iter(invariant, control)
  return invariant ~= control and invariant or nil
end
local function split_iter(t)
  local i = t[0] or 1
  t[0] = i + 1
  return t[i]
end


--- string splitting iterator (plain delimiter).
-- @function isplitn
function _M.isplitn(value, delim, n)
  value, n = splitn_common(value, delim, n, true)
  if n == 0 then
    return noop_iter
  elseif n == 1 then
    return once_iter, value[1]
  end
  return split_iter, value
end


--- string splitting iterator (pattern delimiter).
-- @function ipsplitn
function _M.ipsplitn(value, pattern, n)
  value, n = splitn_common(value, pattern, n, false)
  if n == 0 then
    return noop_iter
  elseif n == 1 then
    return once_iter, value[1]
  end
  return split_iter, value
end



--- strips whitespace from a string.
-- @function strip
function _M.strip(value)
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

  local s = 1 -- position of the leftmost non-whitespace char
  ::spos::
  local b = byte(value, s)
  if not b then -- reached the end of the all whitespace string
    return ""
  end
  if b == SPACE_BYTE or (b >= TAB_BYTE and b <= CR_BYTE) then
    s = s + 1
    goto spos
  end

  local e = -1 -- position of the rightmost non-whitespace char
  ::epos::
  b = byte(value, e)
  if b == SPACE_BYTE or (b >= TAB_BYTE and b <= CR_BYTE) then
    e = e - 1
    goto epos
  end

  if s ~= 1 or e ~= -1 then
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
