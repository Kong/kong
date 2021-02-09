local _M = {}


local string_char = string.char
local string_upper = string.upper
local string_find = string.find
local string_sub = string.sub
local string_byte = string.byte
local string_format = string.format
local tonumber = tonumber
local table_concat = table.concat
local table_clear = require("table.clear")
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
local TMP_OUTPUT = require("table.new")(16, 0)
local DOT = string_byte(".")
local SLASH = string_byte("/")


function _M.normalize(uri, merge_slashes)
  table_clear(TMP_OUTPUT)

  -- Decoding percent-encoded triplets of unreserved characters
  uri = ngx_re_gsub(uri, "%([\\dA-F]{2})", function(m)
    local hex = m[1]
    local num = tonumber(hex, 16)
    if RESERVED_CHARACTERS[num] then
      return string_upper(m[0])
    end

    return string_char(num)
  end, "joi")

  local output_n = 0

  while #uri > 0 do
    local FIRST = string_byte(uri, 1)
    local SECOND = string_byte(uri, 2)
    local THIRD = string_byte(uri, 3)
    local FOURTH = string_byte(uri, 4)

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

  return table_concat(TMP_OUTPUT, "", 1, output_n)
end


function _M.escape(uri)
  return ngx_re_gsub(uri, "[^!#$&'()*+,/:;=?@[\\]A-Z\\d-_.~%]", function(m)
    return string_format("%%%02X", string_byte(m[0]))
  end, "joi")
end


return _M
