local string_char = string.char
local string_upper = string.upper
local string_find = string.find
local string_sub = string.sub
local string_byte = string.byte
local string_format = string.format
local tonumber = tonumber
local table_concat = table.concat
local ngx_re_find = ngx.re.find
local ngx_re_gsub = ngx.re.gsub


local RESERVED_CHARACTERS = {
  [0x21] = true, -- !
  [0x23] = true, -- #
  [0x24] = true, -- $
  [0x25] = true, -- %
  [0x26] = true, -- &
  [0x27] = true, -- '
  [0x28] = true, -- (
  [0x29] = true, -- )
  [0x2A] = true, -- *
  [0x2B] = true, -- +
  [0x2C] = true, -- ,
  [0x2F] = true, -- /
  [0x3A] = true, -- :
  [0x3B] = true, -- ;
  [0x3D] = true, -- =
  [0x3F] = true, -- ?
  [0x40] = true, -- @
  [0x5B] = true, -- [
  [0x5D] = true, -- ]
}


local ESCAPE_PATTERN = "[^!#$&'()*+,/:;=?@[\\]A-Z\\d-_.~%]"

local TMP_OUTPUT = require("table.new")(16, 0)
local DOT = string_byte(".")
local SLASH = string_byte("/")

local function percent_decode(m)
    local hex = m[1]
    local num = tonumber(hex, 16)
    if RESERVED_CHARACTERS[num] then
      return string_upper(m[0])
    end

    return string_char(num)
end


local function percent_escape(m)
  return string_format("%%%02X", string_byte(m[0]))
end


local function escape(uri)
  if ngx_re_find(uri, ESCAPE_PATTERN, "joi") then
    return ngx_re_gsub(uri, ESCAPE_PATTERN, percent_escape, "joi")
  end

  return uri
end


local function unescape(uri, merge_slashes)
  -- check for simple cases and early exit
  if uri == "" or uri == "/" then
    return uri
  end

  -- check if uri needs to be percent-decoded
  -- (this can in some cases lead to unnecessary percent-decoding)
  if string_find(uri, "%", 1, true) then
    -- decoding percent-encoded triplets of unreserved characters
    uri = ngx_re_gsub(uri, "%([\\dA-F]{2})", percent_decode, "joi")
  end

  -- check if the uri contains a dot
  -- (this can in some cases lead to unnecessary dot removal processing)
  if string_find(uri, ".", 1, true) == nil  then
    if not merge_slashes then
      return uri
    end

    if string_find(uri, "//", 1, true) == nil then
      return uri
    end
  end

  local output_n = 0

  while #uri > 0 do
    local FIRST = string_byte(uri, 1)
    local SECOND = FIRST and string_byte(uri, 2) or nil
    local THIRD = SECOND and string_byte(uri, 3) or nil
    local FOURTH = THIRD and string_byte(uri, 4) or nil

    if uri == "/." then -- /.
      uri = "/"

    elseif uri == "/.." then -- /..
      uri = "/"
      if output_n > 0 then
        output_n = output_n - 1
      end

    elseif uri == "." or uri == ".." then
      uri = ""

    elseif FIRST == DOT and SECOND == DOT and THIRD == SLASH then -- ../
      uri = string_sub(uri, 4)

    elseif FIRST == DOT and SECOND == SLASH then -- ./
      uri = string_sub(uri, 3)

    elseif FIRST == SLASH and SECOND == DOT and THIRD == SLASH then -- /./
      uri = string_sub(uri, 3)

    elseif FIRST == SLASH and SECOND == DOT and THIRD == DOT and FOURTH == SLASH then -- /../
      uri = string_sub(uri, 4)
      if output_n > 0 then
        output_n = output_n - 1
      end

    elseif merge_slashes and FIRST == SLASH and SECOND == SLASH then -- //
      uri = string_sub(uri, 2)

    else
      local i = string_find(uri, "/", 2, true)
      output_n = output_n + 1

      if i then
        local seg = string_sub(uri, 1, i - 1)
        TMP_OUTPUT[output_n] = seg
        uri = string_sub(uri, i)

      else
        TMP_OUTPUT[output_n] = uri
        uri = ""
      end
    end
  end

  if output_n == 0 then
    return ""
  end

  if output_n == 1 then
    return TMP_OUTPUT[1]
  end

  return table_concat(TMP_OUTPUT, nil, 1, output_n)
end


local function normalize(uri, merge_slashes)
  return escape(unescape(uri, merge_slashes))
end


return {
  escape = escape,
  unescape = unescape,
  normalize = normalize,
}
