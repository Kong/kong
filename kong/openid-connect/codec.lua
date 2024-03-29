-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local base64  = require "ngx.base64"
local json    = require "cjson.safe"
local str     = require "resty.string"


local encode_base64    = ngx.encode_base64
local decode_base64    = ngx.decode_base64
local encode_base64url = base64.encode_base64url
local decode_base64url = base64.decode_base64url
local encode_args      = ngx.encode_args
local decode_args      = ngx.decode_args
local escape_uri       = ngx.escape_uri
local unescape_uri     = ngx.unescape_uri
local find             = string.find
local sub              = string.sub
local to_hex           = str.to_hex

local function from_hex(s)
  local ok, v = pcall(string.gsub, s, "..", function (digits)
      return string.char(tonumber(digits, 16))
  end)

  if ok then
    return v
  end
  return nil, "unable to decode base16 data"
end


return {
  json   = {
    encode = json.encode,
    decode = json.decode,
  },
  base16 = {
    encode = to_hex,
    decode = function(s)
      local err2
      local enc, err = from_hex(s)
      if not enc then
        enc, err2 = from_hex("0" .. s)
      end
      if not enc then
        return nil, err or err2
      end
      return enc
    end,
  },
  base64 = {
    encode = function(s)
      local enc, err = encode_base64(s)
      if not enc then
        return nil, err
      end
      return enc
    end,
    decode = function(s)
      local dec = decode_base64(s)
      if not dec then
        return nil, "unable to decode base64 data"
      end
      return dec
    end,
  },
  base64url = {
    encode = function(s)
      local enc, err = encode_base64url(s)
      if not enc then
        return nil, err
      end
      return enc
    end,
    decode = function(s)
      local dec, err = decode_base64url(s)
      if not dec then
        return nil, "unable to decode base64url data:" .. err
      end
      return dec
    end,
  },
  args = {
    encode = encode_args,
    decode = decode_args,
  },
  uri = {
    encode = escape_uri,
    decode = unescape_uri,
  },
  credentials = {
    encode = function(i, s)
      local enc, err = encode_base64(i .. ":" .. s)
      if not enc then
        return nil, err
      end
      return enc
    end,
    decode = function(v)
      local d, err = decode_base64(v)
      if not d then
        return nil, err
      end

      local p = find(d, ":", 2, true)
      if not p then
        return nil, "invalid credentials"
      end

      local i = sub(d, 1, p - 1)
      local s = sub(d, p + 1)

      return i, s
    end,
  },
  none = {
    encode = function(s)
      return s
    end,
    decode = function(s)
      return s
    end,
  }
}
