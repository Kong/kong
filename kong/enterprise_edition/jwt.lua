-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- JWT
-- Adapted from kong.plugins.jwt.jwt_parser

local openssl_mac   = require "resty.openssl.mac"
local cjson         = require "cjson.safe"
local pl_string     = require "pl.stringx"
local string_rep    = string.rep
local table_concat  = table.concat
local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64
local concat        = table.concat


local _M = {}


_M.INVALID_JWT = "Invalid JWT"
_M.EXPIRED_JWT = "Expired JWT"


local algs = {
  ["HS256"] = function (data, secret) return openssl_mac.new(secret, "HMAC", nil, "sha256"):final(data) end,
}

--- base 64 encoding
-- @param input String to base64 encode
-- @return Base64 encoded string
local function b64_encode(input)
  local result = encode_base64(input)
  result = result:gsub("+", "-"):gsub("/", "_"):gsub("=", "")
  return result
end


--- base 64 decode
-- @param input String to base64 decode
-- @return Base64 decoded string
local function b64_decode(input)
  local remainder = #input % 4

  if remainder > 0 then
    local padlen = 4 - remainder
    input = input .. string_rep('=', padlen)
  end

  input = input:gsub("-", "+"):gsub("_", "/")
  return decode_base64(input)
end


_M.verify_signature = function(jwt, secret)
  local signing_func = algs[jwt.header.alg]
  if not signing_func then
    return nil, "invalid alg"
  end

  return jwt.signature == signing_func(jwt.header_64 .. "." .. jwt.claims_64, secret)
end


_M.generate_JWT = function(claims, secret, alg)
  local header = {
    typ = "JWT",
    alg = alg or "HS256"
  }

  local signing_func = algs[header.alg]
  if not signing_func then
    return nil, "invalid alg"
  end

  -- encode header and claims
  local segments = {
    b64_encode(cjson.encode(header)),
    b64_encode(cjson.encode(claims)),
  }

  -- concat header and claims to generate signature
  local data = table_concat(segments, ".")
  local signature = signing_func(data, secret)

  -- concat encoded signature to header and claims, done!
  return data .. "." .. b64_encode(signature)
end


_M.parse_JWT = function(jwt)
  if type(jwt) ~= "string" or jwt == "" then
    return nil, _M.INVALID_JWT
  end

  local header_64, claims_64, signature_64 = unpack(pl_string.split(jwt, "."))

  local header, err = cjson.decode(b64_decode(header_64))
  if err then
    return nil, _M.INVALID_JWT
  end

  local claims, err = cjson.decode(b64_decode(claims_64))
  if err then
    return nil, _M.INVALID_JWT
  end

  local signature = b64_decode(signature_64)

  return {
    header = header,
    claims = claims,
    signature = signature,
    header_64 = header_64,
    claims_64 = claims_64,
    signature_64 = signature_64,
  }
end

_M.find_claim = function (payload, search)
  -- Return nil if payload is not a table
  if type(payload) ~= "table" then
    return nil
  end

  -- Get the type of search
  local search_t = type(search)
  local t = payload
  if search_t == "string" then
    -- Return nil if value at specified location does not exist
    if not t[search] then
      return nil
    end

    t = t[search]

  elseif search_t == "table" then
    -- Iterate through elements of search table and access corresponding nested values in payload
    for _, claim in ipairs(search) do
      if not t[claim] then
        return nil
      end

      t = t[claim]
    end

  else
    -- Return nil if search is not a string or table
    return nil
  end

  -- Return string representation of value at specified location in payload
  if type(t) == "table" then
    return concat(t, " ")
  end

  return tostring(t)
end


return _M
