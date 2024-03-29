-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local deflate   = require "kong.openid-connect.deflate"
local debug     = require "kong.openid-connect.debug"
local codec     = require "kong.openid-connect.codec"
local jwa       = require "kong.openid-connect.jwa"


local base64url = codec.base64url
local tostring  = tostring
local concat    = table.concat
local upper     = string.upper
local json      = codec.json
local type      = type
local find      = string.find
local sub       = string.sub


local function split(jwt)
  local t = {}
  local i = 1
  local b = 1
  local e = find(jwt, ".", b, true)
  while e do
    t[i] = sub(jwt, b, e - 1)
    i = i + 1
    b = e + 1
    e = find(jwt, ".", b, true)
  end
  t[i] = sub(jwt, b)
  return t, i
end


local jws = {}


function jws.encode(token)
  if type(token) ~= "table" then
    return nil, "token needs to be a table"
  end

  local jwk = token.jwk
  if not jwk then
    jwk = {
      alg = "RS256",
    }
  end

  jwk.alg = jwk.alg or "RS256"

  local header = token[1] or token.header
  if not header then
    header = {
      typ = "JWT",
      alg = jwk.alg,
      kid = jwk.kid,
    }
  end

  local header_encoded, payload_encoded, err

  if type(header) == "table" then
    header_encoded, err = json.encode(header)
    if not header_encoded then
      return nil, "unable to json encode jws header (" .. err .. ")"
    end
  else
    header_encoded = tostring(header)
  end

  header_encoded, err = base64url.encode(header_encoded)
  if not header_encoded then
    return nil, "unable to base64 encode jws header (" .. err .. ")"
  end

  local payload = token[2] or token.payload
  if not payload then
    payload = {}
  end

  if type(payload) == "table" then
    payload_encoded, err = json.encode(payload)
    if not payload_encoded then
      return nil, "unable to json encode jws payload (" .. err .. ")"
    end
  else
    payload_encoded = tostring(payload)
  end

  payload_encoded, err = base64url.encode(payload_encoded)
  if not payload_encoded then
    return nil, "unable to base64 encode jws payload (" .. err .. ")"
  end

  local message = concat({ header_encoded, payload_encoded }, ".")
  local digest
  digest, err = jwa.sign(header.alg, jwk, message)
  if not digest then
    return nil, err
  end

  return concat({ message, digest }, ".")
end


function jws.decode(token, options, oic)
  options = options or {}
  oic     = oic     or { options = {} }

  local t = type(token)
  if t ~= "table" then
    if t ~= "string" then
      return nil,  "token needs to be a table or a string"
    end

    local z
    token, z = split(token)
    if z ~= 3 then
      return nil, "invalid jws token was specified"
    end
  end

  local header  = token[1] or token.header
  local payload = token[2] or token.payload
  local sig     = token[3] or token.signature

  local hdr, pld, ok, err

  hdr, err = base64url.decode(header)
  if not hdr then
    return nil, "unable to base64url decode jws header (" ..  err .. ")"
  end

  hdr, err = json.decode(hdr)
  if not hdr then
    return nil, "unable to json decode jws header (" ..  err .. ")"
  end

  if type(hdr) ~= "table" then
    return nil, "json decoding jws header resulted invalid type (" .. type(hdr) .. ")"
  end

  local jwk

  local verify_signature = true
  if options.verify_signature ~= nil then
    verify_signature = not not options.verify_signature
  elseif oic.options.verify_signature ~= nil then
    verify_signature = not not oic.options.verify_signature
  end

  if verify_signature then
    if hdr.typ then
      local upper_typ = upper(hdr.typ)
      if upper_typ ~= "JWT" and upper_typ ~= "AT+JWT" then
        return nil, "only jwts are supported for the jws"
      end
    end

    local alg = hdr.alg
    if not alg then
      return nil, "jws algorithm was not specified"
    end

    local enable_hs_signatures = false
    if options.enable_hs_signatures ~= nil then
      enable_hs_signatures = not not options.enable_hs_signatures
    elseif oic.options.enable_hs_signatures ~= nil then
      enable_hs_signatures = not not oic.options.enable_hs_signatures
    end

    if jwa.HMAC[alg] and not enable_hs_signatures then
      return nil, "jws algorithm (" .. alg .. ") is disabled"
    end

    local keys1 = options.keys or {}
    local keys2 =     oic.keys or {}

    local kid = hdr.kid
    local x5t = hdr.x5t

    if x5t == kid then
      x5t = nil
    end

    if kid and x5t then
      local ckey  = kid .. ":" .. alg
      local ckey2 = x5t .. ":" .. alg
      jwk = keys1[ckey] or keys1[ckey2] or keys1[kid] or keys1[x5t] or
        keys2[ckey] or keys2[ckey2] or keys2[kid] or keys2[x5t]

      if not jwk and keys1.rediscover then
        keys1, err = keys1:rediscover()
        if err then
          debug(err)
        end

        keys1 = keys1 or {}

        if type(keys1) == "table" then
          jwk = keys1[ckey] or keys1[ckey2] or keys1[kid] or keys1[x5t]
        end
      end

      if not jwk and keys2.rediscover then
        keys2, err = keys2:rediscover()
        if err then
          debug(err)
        end

        keys2 = keys2 or {}

        if type(keys2) == "table" then
          jwk = keys2[ckey] or keys2[ckey2] or keys2[kid] or keys2[x5t]
        end
      end

    elseif kid then
      local ckey = kid .. ":" .. alg
      jwk = keys1[ckey] or keys1[kid] or keys2[ckey] or keys2[kid]

      if not jwk and keys1.rediscover then
        keys1, err = keys1:rediscover()
        if err then
          debug(err)
        end

        keys1 = keys1 or {}

        if type(keys1) == "table" then
          jwk = keys1[ckey] or keys1[kid]
        end
      end

      if not jwk and keys2.rediscover then
        keys2, err = keys2:rediscover()
        if err then
          debug(err)
        end

        keys2 = keys2 or {}

        if type(keys2) == "table" then
          jwk = keys2[ckey] or keys2[kid]
        end
      end

    elseif x5t then
      local ckey = x5t .. ":" .. alg
      jwk = keys1[ckey] or keys1[x5t] or keys2[ckey] or keys2[x5t]

      if not jwk and keys1.rediscover then
        keys1, err = keys1:rediscover()
        if err then
          debug(err)
        end

        keys1 = keys1 or {}

        if type(keys1) == "table" then
          jwk = keys1[ckey] or keys1[x5t]
        end
      end

      if not jwk and keys2.rediscover then
        keys2, err = keys2:rediscover()
        if err then
          debug(err)
        end

        keys2 = keys2 or {}

        if type(keys2) == "table" then
          jwk = keys2[ckey] or keys2[x5t]
        end
      end
    end

    if not jwk then
      if jwa.HMAC[alg] and enable_hs_signatures then
        jwk = keys1[alg] or keys1.default or keys2[alg] or keys2.default

      else
        jwk = keys1[alg] or keys2[alg]
      end

      if not kid and not x5t and not jwk and keys1.rediscover then
        keys1, err = keys1:rediscover()
        if err then
          debug(err)
        end

        keys1 = keys1 or {}

        if type(keys1) == "table" then
          jwk = keys1[alg]
        end
      end

      if not kid and not x5t and not jwk and keys2.rediscover then
        keys2, err = keys2:rediscover()
        if err then
          debug(err)
        end

        keys2 = keys2 or {}

        if type(keys2) == "table" then
          jwk = keys2[alg]
        end
      end
    end

    if not jwk then
      return nil, "suitable jwk was not found (" .. alg .. "/" .. (kid or x5t or "unknown") .. ")"
    end

    local inp = concat({ header, payload }, ".")

    ok, err = jwa.verify(alg, jwk, inp, sig)
    if not ok then
      return nil, err
    end
  end

  if hdr.b64 ~= false then
    pld, err = base64url.decode(payload)
    if not pld then
      return nil, "unable to base64 url decode jws payload (" ..  err .. ")"
    end
  end

  -- TODO: this function requires that the JWT payload is a JSON string, this might not always be the case

  if hdr.zip == "DEF" then
    local inflated_pld
    inflated_pld, err = deflate.decompress(pld)
    if inflated_pld then
      pld, err = json.decode(inflated_pld)
      if not pld then
        return nil, "unable to json decode inflated jws payload (" ..  err .. ")"
      end

    elseif err then
      pld = json.decode(pld) -- fallback (perhaps the payload was not deflated despite the header)
      if not pld then
        -- the fallback didn't work either
        return nil, "unable to inflate jws payload (" ..  err .. ")"
      end

    else
      -- this should not happen, but perhaps inflation returns nil without error in some edge case
      pld, err = json.decode(pld)
      if not pld then
        return nil, "unable to json decode jws payload (" ..  err .. ") after inflation resulted nil value"
      end
    end

  else
    pld, err = json.decode(pld)
    if not pld then
      return nil, "unable to json decode jws payload (" ..  err .. ")"
    end
  end

  return {
    jwk       = jwk,
    type      = "JWS",
    header    = hdr,
    payload   = pld,
    signature = sig,
  }
end


return jws
