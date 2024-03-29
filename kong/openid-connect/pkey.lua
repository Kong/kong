-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local codec          = require "kong.openid-connect.codec"
local jwk_validation = require "kong.openid-connect.validation.jwk"
local hash           = require "kong.openid-connect.hash"
local openssl_pkey   = require "resty.openssl.pkey"
local lrucache       = require "resty.lrucache"

local base64url    = codec.base64url
local validate_jwk = jwk_validation.validate
local json         = codec.json
local fmt          = string.format

local CACHE_SIZE = 512
local cache      = lrucache.new(CACHE_SIZE)

local function errmsg(msg, err)
  return fmt("%s (%s)", msg, err)
end

local function cache_key(json_jwk, kty, type)
  return hash.S256(fmt("%s:%s:%s",
    json_jwk,
    kty,
    type
  ))
end

local pkey = {}

pkey.__index = pkey

local function get_openssl_pkey(jwk, kty, type)
  if not (jwk and kty and type) then
    return nil, "failed loading pkey: jwk, kty and type are required"
  end

  local json_jwk, err
  jwk, err = validate_jwk(kty, type, jwk)
  if not jwk then
    return nil, err
  end
  jwk.kty = kty
  json_jwk, err = json.encode(jwk)
  if not json_jwk then
    return nil, errmsg("json encode failed", err)
  end

  local pk = cache:get(cache_key(json_jwk, kty, type))
  if pk then
    return pk
  end
  pk, err = openssl_pkey.new(
    json_jwk,
    { format = "JWK" }
  )
  if not pk then
    return nil, errmsg("failed instantiating key", err)
  end

  cache:set(cache_key(json_jwk, kty, type), pk)
  return pk
end

function pkey.sign(kty, alg, jwk, inp, padding, opts)
  local pk, err = get_openssl_pkey(jwk, kty, "s")
  if not pk then
    return nil, err
  end
  local sig
  sig, err = pk:sign(inp, alg, padding, opts)
  if err then
    return nil, errmsg("signature failed", err)
  end
  return base64url.encode(sig)
end

function pkey.verify(kty, alg, jwk, inp, sig, padding, opts)
  local pk, err = get_openssl_pkey(jwk, kty, "v")
  if not pk then
    return nil, err
  end
  local dc_sig
  dc_sig, err = base64url.decode(sig)
  if not dc_sig then
    return nil, errmsg("signature could not be base64 url decoded", err)
  end
  return pk:verify(dc_sig, inp, alg, padding, opts)
end

return pkey
