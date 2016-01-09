-- JWT verification module
-- Adapted version of x25/luajwt for Kong. It provides various improvements and
-- an OOP architecture allowing the JWT to be parsed and verified separatly,
-- avoiding multiple parsings.
--
-- @see https://github.com/x25/luajwt

local json = require "cjson"
local base64 = require "base64"
local crypto = require "crypto"
local utils = require "kong.tools.utils"

local error = error
local type = type
local pcall = pcall
local ngx_time = ngx.time
local string_rep = string.rep
local setmetatable = setmetatable

--- Supported algorithms for signing tokens.
-- Only support HS256 for our use case.
local alg_sign = {
  ["HS256"] = function(data, key) return crypto.hmac.digest("sha256", data, key, true) end
  --["HS384"] = function(data, key) return crypto.hmac.digest("sha384", data, key, true) end,
  --["HS512"] = function(data, key) return crypto.hmac.digest("sha512", data, key, true) end
}

--- Supported algorithms for verifying tokens.
-- Only support HS256 for our use case.
local alg_verify = {
  ["HS256"] = function(data, signature, key) return signature == alg_sign["HS256"](data, key) end
  --["HS384"] = function(data, signature, key) return signature == alg_sign["HS384"](data, key) end,
  --["HS512"] = function(data, signature, key) return signature == alg_sign["HS512"](data, key) end
}

--- base 64 encoding
-- @param input String to base64 encode
-- @return Base64 encoded string
local function b64_encode(input)
  local result = base64.encode(input)
  result = result:gsub("+", "-"):gsub("/", "_"):gsub("=", "")
  return result
end

--- base 64 decode
-- @param input String to base64 decode
-- @return Base64 decoded string
local function b64_decode(input)
  local reminder = #input % 4

  if reminder > 0 then
    local padlen = 4 - reminder
    input = input..string_rep('=', padlen)
  end

  input = input:gsub("-", "+"):gsub("_", "/")
  return base64.decode(input)
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
    return nil, "Invalid JSON"
  end

  if not header.typ or header.typ ~= "JWT" then
    return nil, "Invalid typ"
  end

  if not header.alg or type(header.alg) ~= "string" or not alg_verify[header.alg] then
    return nil, "Invalid alg"
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
  if type(data) ~= "table" then error("Argument #1 must be table", 2) end
  if type(key) ~= "string" then error("Argument #2 must be string", 2) end
  if header and type(header) ~= "table" then error("Argument #4 must be a table", 2) end

  alg = alg or "HS256"

  if not alg_sign[alg] then
    error("Algorithm not supported", 2)
  end

  local header = header or {typ = "JWT", alg = alg}
  local segments = {
    b64_encode(json.encode(header)),
    b64_encode(json.encode(data))
  }

  local signing_input = table.concat(segments, ".")
  local signature = alg_sign[alg](signing_input, key)
  segments[#segments+1] = b64_encode(signature)
  return table.concat(segments, ".")
end

--[[

  JWT public interface

]]--

local _M = {}
_M.__index = _M

--- Instanciate a JWT parser
-- Parse a JWT and instanciate a JWT parser for further operations
-- Return errors instead of an instance if any encountered
-- @param token JWT to parse
-- @return JWT parser
-- @return error if any
function _M:new(token)
  if type(token) ~= "string" then error("JWT must be a string", 2) end

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
  return alg_verify[self.header.alg](self.header_64.."."..self.claims_64, self.signature, key)
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
  if not claims_to_verify then claims_to_verify = {} end
  local errors = nil
  local claim, claim_rules

  for _, claim_name in pairs(claims_to_verify) do
    claim = self.claims[claim_name]
    claim_rules = registered_claims[claim_name]
    if type(claim) ~= claim_rules.type then
      errors = utils.add_error(errors, claim_name, "must be a "..claim_rules.type)
    else
      local check_err = claim_rules.check(claim)
      if check_err then
        errors = utils.add_error(errors, claim_name, check_err)
      end
    end
  end

  return errors == nil, errors
end

_M.encode = encode_token

return _M
