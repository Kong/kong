-- JWT verification module
-- Adapted version of x25/luajwt for Kong. It provides various improvements and
-- an OOP architecture allowing the JWT to be parsed and verified separately,
-- avoiding multiple parsings.
--
-- @see https://github.com/x25/luajwt

local json = require "cjson"
local utils = require "kong.tools.utils"
local openssl_digest = require "openssl.digest"
local openssl_hmac = require "openssl.hmac"
local openssl_pkey = require "openssl.pkey"
local asn_sequence = require "kong.plugins.jwt.asn_sequence"

local error = error
local type = type
local pcall = pcall
local ngx_time = ngx.time
local string_rep = string.rep
local string_sub = string.sub
local table_concat = table.concat
local setmetatable = setmetatable
local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64

--- Supported algorithms for signing tokens.
local alg_sign = {
  ["HS256"] = function(data, key) return openssl_hmac.new(key, "sha256"):final(data) end,
  ["HS384"] = function(data, key) return openssl_hmac.new(key, "sha384"):final(data) end,
  ["HS512"] = function(data, key) return openssl_hmac.new(key, "sha512"):final(data) end,
  ["RS256"] = function(data, key) return openssl_pkey.new(key):sign(openssl_digest.new("sha256"):update(data)) end,
  ["RS512"] = function(data, key) return openssl_pkey.new(key):sign(openssl_digest.new("sha512"):update(data)) end,
  ["ES256"] = function(data, key)
    local pkeyPrivate = openssl_pkey.new(key)
    local signature = pkeyPrivate:sign(openssl_digest.new("sha256"):update(data))

    local derSequence = asn_sequence.parse_simple_sequence(signature)
    local r = asn_sequence.unsign_integer(derSequence[1], 32)
    local s = asn_sequence.unsign_integer(derSequence[2], 32)
    assert(#r == 32)
    assert(#s == 32)
    return r .. s
  end
}

--- Supported algorithms for verifying tokens.
local alg_verify = {
  ["HS256"] = function(data, signature, key) return signature == alg_sign["HS256"](data, key) end,
  ["HS384"] = function(data, signature, key) return signature == alg_sign["HS384"](data, key) end,
  ["HS512"] = function(data, signature, key) return signature == alg_sign["HS512"](data, key) end,
  ["RS256"] = function(data, signature, key)
    local pkey_ok, pkey = pcall(openssl_pkey.new, key)
    assert(pkey_ok, "Consumer Public Key is Invalid")
    local digest = openssl_digest.new('sha256'):update(data)
    return pkey:verify(signature, digest)
  end,
  ["RS512"] = function(data, signature, key)
    local pkey_ok, pkey = pcall(openssl_pkey.new, key)
    assert(pkey_ok, "Consumer Public Key is Invalid")
    local digest = openssl_digest.new('sha512'):update(data)
    return pkey:verify(signature, digest)
  end,
  ["ES256"] = function(data, signature, key)
    local pkey_ok, pkey = pcall(openssl_pkey.new, key)
    assert(pkey_ok, "Consumer Public Key is Invalid")
    assert(#signature == 64, "Signature must be 64 bytes.")
    local asn = {}
    asn[1] = asn_sequence.resign_integer(string_sub(signature, 1, 32))
    asn[2] = asn_sequence.resign_integer(string_sub(signature, 33, 64))
    local signatureAsn = asn_sequence.create_simple_sequence(asn)
    local digest = openssl_digest.new('sha256'):update(data)
    return pkey:verify(signatureAsn, digest)
  end
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

--- Tokenize a string by delimiter
-- Used to separate the header, claims and signature part of a JWT
-- @param str String to tokenize
-- @param div Delimiter
-- @param len Number of parts to retrieve
-- @return A table of strings
local function tokenize(str, div, len)
  local result, pos = {}, 0

  for st, sp in function() return str:find(div, pos, true) end do
    result[#result + 1] = str:sub(pos, st-1)
    pos = sp + 1
    len = len - 1
    if len <= 1 then
      break
    end
  end

  result[#result + 1] = str:sub(pos)
  return result
end

--- Parse a JWT
-- Parse a JWT and validate header values.
-- @param token JWT to parse
-- @return A table containing base64 and decoded headers, claims and signature
local function decode_token(token)
  -- Get b64 parts
  local header_64, claims_64, signature_64 = unpack(tokenize(token, ".", 3))

  -- Decode JSON
  local ok, header, claims, signature = pcall(function()
    return json.decode(b64_decode(header_64)),
           json.decode(b64_decode(claims_64)),
           b64_decode(signature_64)
  end)
  if not ok then
    return nil, "invalid JSON"
  end

  if header.typ and header.typ:upper() ~= "JWT" then
    return nil, "invalid typ"
  end

  if not header.alg or type(header.alg) ~= "string" or not alg_verify[header.alg] then
    return nil, "invalid alg"
  end

  if not claims then
    return nil, "invalid claims"
  end

  if not signature then
    return nil, "invalid signature"
  end

  return {
    token = token,
    header_64 = header_64,
    claims_64 = claims_64,
    signature_64 = signature_64,
    header = header,
    claims = claims,
    signature = signature
  }
end

-- For test purposes
local function encode_token(data, key, alg, header)
  if type(data) ~= "table" then
    error("Argument #1 must be table", 2)
  end
  if type(key) ~= "string" then
    error("Argument #2 must be string", 2)
  end
  if header and type(header) ~= "table" then
    error("Argument #4 must be a table", 2)
  end

  alg = alg or "HS256"

  if not alg_sign[alg] then
    error("Algorithm not supported", 2)
  end

  local header = header or {typ = "JWT", alg = alg}
  local segments = {
    b64_encode(json.encode(header)),
    b64_encode(json.encode(data))
  }

  local signing_input = table_concat(segments, ".")
  local signature = alg_sign[alg](signing_input, key)
  segments[#segments+1] = b64_encode(signature)
  return table_concat(segments, ".")
end

--[[

  JWT public interface

]]--

local _M = {}
_M.__index = _M

--- Instantiate a JWT parser
-- Parse a JWT and instantiate a JWT parser for further operations
-- Return errors instead of an instance if any encountered
-- @param token JWT to parse
-- @return JWT parser
-- @return error if any
function _M:new(token)
  if type(token) ~= "string" then
    error("Token must be a string, got " .. tostring(token), 2)
  end

  local token, err = decode_token(token)
  if err then
    return nil, err
  end

  return setmetatable(token, _M)
end

--- Verify a JWT signature
-- Verify the current JWT signature against a given key
-- @param key Key against which to verify the signature
-- @return A boolean indicating if the signature if verified or not
function _M:verify_signature(key)
  return alg_verify[self.header.alg](self.header_64 .. "." .. self.claims_64, self.signature, key)
end

function _M:b64_decode(input)
  return b64_decode(input)
end

--- Registered claims according to RFC 7519 Section 4.1
local registered_claims = {
  ["nbf"] = {
    type = "number",
    check = function(nbf)
      if nbf > ngx_time() then
        return "token not valid yet"
      end
    end
  },
  ["exp"] = {
    type = "number",
    check = function(exp)
      if exp <= ngx_time() then
        return "token expired"
      end
    end
  }
}

--- Verify registered claims (according to RFC 7519 Section 4.1)
-- Claims are verified by type and a check.
-- @param claims_to_verify A list of claims to verify.
-- @return A boolean indicating true if no errors zere found
-- @return A list of errors
function _M:verify_registered_claims(claims_to_verify)
  if not claims_to_verify then
    claims_to_verify = {}
  end
  local errors = nil
  local claim, claim_rules

  for _, claim_name in pairs(claims_to_verify) do
    claim = self.claims[claim_name]
    claim_rules = registered_claims[claim_name]
    if type(claim) ~= claim_rules.type then
      errors = utils.add_error(errors, claim_name, "must be a " .. claim_rules.type)
    else
      local check_err = claim_rules.check(claim)
      if check_err then
        errors = utils.add_error(errors, claim_name, check_err)
      end
    end
  end

  return errors == nil, errors
end

--- Check that the maximum allowed expiration is not reached
-- @param maximum_expiration of the claim
-- @return A Boolean indicating true if the claim has reached the maximum
-- allowed expiration time
-- @return error if any
function _M:check_maximum_expiration(maximum_expiration)
  if maximum_expiration <= 0 then
    return true
  end

  local exp = self.claims["exp"]
  if exp == nil or exp - ngx_time() > maximum_expiration then
    return false, {exp = "exceeds maximum allowed expiration"}
  end

  return true
end

_M.encode = encode_token

return _M
