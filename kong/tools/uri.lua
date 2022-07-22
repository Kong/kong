local table_new = require "table.new"

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

-- Charset:
--   reserved = "!" / "*" / "'" / "(" / ")" / ";" / ":" /
--       "@" / "&" / "=" / "+" / "$" / "," / "/" / "?" / "%" / "#" / "[" / "]"
--   unreserved  = ALPHA / DIGIT / "-" / "." / "_" / "~"
--   other: * (meaning any char that is not mentioned above)

-- Reserved characters have special meaning in URI. Encoding/decoding it affects the semantics of the URI;
-- Unreserved characters are safe to use as part of HTTP message without encoding;
-- Other characters has not special meaning but may be not safe to use as part of HTTP message without encoding;

-- We should not unescape or escape reserved characters;
-- We should unescape but not escape unreserved characters;
-- We choose to unescape when processing and escape when forwarding for other characters

local RESERVED_CHARS = "!*'();:@&=+$,/?%#[]"

local chars_to_decode = table_new(256, 0)
do
  -- reserved
  for i = 1, #RESERVED_CHARS do
    chars_to_decode[string_byte(RESERVED_CHARS, i)] = true
  end

  -- unreserved and others default to nil
end


local ESCAPE_PATTERN = "[^!#$&'()*+,/:;=?@[\\]A-Z\\d-_.~%]"

local TMP_OUTPUT = require("table.new")(16, 0)
local DOT = string_byte(".")
local SLASH = string_byte("/")


local function normalize_decode(m)
  local hex = m[1]
  local num = tonumber(hex, 16)

  -- from rfc3986 we should decode unreserved character
  -- and we choose to decode "others"
  if not chars_to_decode[num] then -- is not reserved(false or nil)
    return string_char(num)
  end

  return string_upper(m[0])
end


local function percent_escape(m)
  return string_format("%%%02X", string_byte(m[0]))
end

-- This function does slightly different things from its name.
-- It ensures the output to be safe to a part of HTTP message (headers or path)
-- and preserve origin semantics
local function escape(uri)
  if ngx_re_find(uri, ESCAPE_PATTERN, "joi") then
    return (ngx_re_gsub(uri, ESCAPE_PATTERN, percent_escape, "joi"))
  end

  return uri
end


local function normalize(uri, merge_slashes)
  -- check for simple cases and early exit
  if uri == "" or uri == "/" then
    return uri
  end

  -- check if uri needs to be percent-decoded
  -- (this can in some cases lead to unnecessary percent-decoding)
  if string_find(uri, "%", 1, true) then
    -- decoding percent-encoded triplets of unreserved characters
    uri = ngx_re_gsub(uri, "%([\\dA-F]{2})", normalize_decode, "joi")
  end

  -- check if the uri contains a dot
  -- (this can in some cases lead to unnecessary dot removal processing)
  -- notice: it's expected that /%2e./ is considered the same of /../
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


return {
  escape = escape,
  normalize = normalize,
}
