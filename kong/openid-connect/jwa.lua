-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local hash           = require "kong.openid-connect.hash"
local codec          = require "kong.openid-connect.codec"
local nyi            = require "kong.openid-connect.nyi"
local validate_jwk   = require "kong.openid-connect.validation.jwk".validate
local pkey           = require "kong.openid-connect.pkey"
local openssl_pkey   = require "resty.openssl.pkey"
local openssl_hmac   = require "resty.openssl.hmac"

local base64url    = codec.base64url
local fmt          = string.format
local type         = type


local function errmsg(msg, err)
  if err then
    return fmt("%s (%s)", msg, err)
  end

  return msg
end


local S256 = hash.S256
local S384 = hash.S384
local S512 = hash.S512


local HASH = {
  S256 = S256,
  S384 = S384,
  S512 = S512,
  HS256 = S256,
  HS384 = S384,
  HS512 = S512,
  RS256 = S256,
  RS384 = S384,
  RS512 = S512,
  ES256 = S256,
  ES384 = S384,
  ES512 = S512,
  PS256 = S256,
  PS384 = S384,
  PS512 = S512,
}


local HS = {}


function HS.sign(alg, jwk, inp)
  local v_jwk, err = validate_jwk("HS", "s", jwk)
  if not v_jwk then
    return nil, err
  end

  local k
  k, err = base64url.decode(v_jwk.k)
  if not k then
    return nil, errmsg("hs key value could not be base64 url decoded", err)
  end

  local hmac
  hmac, err = openssl_hmac.new(k, alg)
  if not hmac then
    return nil, errmsg("failed instantiating mac", err)
  end

  local sig
  sig, err = hmac:final(inp)
  if err then
    return nil, errmsg("unable to sign hs digest", err)
  end
  sig, err = base64url.encode(sig)
  if not sig then
    return nil, errmsg("unable to base64 url encode hs signature", err)
  end
  return sig
end


function HS.verify(alg, jwk, inp, sig)
  if not sig then
    return nil, "hs signature was not specified"
  end
  local ds, err = base64url.decode(sig)
  if not ds then
    return nil, errmsg("hs signature could not be base64 url decoded", err)
  end

  local mac
  mac, err = HS.sign(alg, jwk, inp)
  if not mac then
    return nil, err
  end

  if mac == sig then
    return true
  end
  return nil, "hs signature verification failed"
end


local RS = {}


function RS.sign(alg, jwk, inp)
  return pkey.sign("RSA", alg, jwk, inp)
end


function RS.verify(alg, jwk, inp, sig)
  return pkey.verify("RSA", alg, jwk, inp, sig)
end


function RS.encrypt()
  return nyi()
end


function RS.decrypt()
  return nyi()
end


local PS = {}


function PS.sign(alg, jwk, inp)
  return pkey.sign("RSA", alg, jwk, inp,
    openssl_pkey.PADDINGS.RSA_PKCS1_PSS_PADDING
  )
end


function PS.verify(alg, jwk, inp, sig)
  return pkey.verify("RSA", alg, jwk, inp,
    sig, openssl_pkey.PADDINGS.RSA_PKCS1_PSS_PADDING
  )
end


function PS.encrypt()
  return nyi()
end


function PS.decrypt()
  return nyi()
end


local ES = {}


function ES.sign(alg, jwk, inp, raw_signature)
  local use_raw = true
  if raw_signature == false then
    use_raw = false
  end
  return pkey.sign("EC", alg, jwk, inp, nil, {ecdsa_use_raw = use_raw})
end


function ES.verify(alg, jwk, inp, sig, raw_signature)
  local use_raw = true
  if raw_signature == false then
    use_raw = false
  end
  return pkey.verify("EC", alg, jwk, inp, sig, nil, {ecdsa_use_raw = use_raw})
end


function ES.encrypt()
  return nyi()
end


function ES.decrypt()
  return nyi()
end


local EdDSA = {}


function EdDSA.sign(jwk, inp)
  return pkey.sign("OKP", nil, jwk, inp)
end


function EdDSA.verify(jwk, inp, sig)
  return pkey.verify("OKP", nil, jwk, inp, sig)
end


local HS256 = {}


function HS256.sign(...)
  return HS.sign("SHA256", ...)
end


function HS256.verify(...)
  return HS.verify("SHA256", ...)
end


local HS384 = {}


function HS384.sign(...)
  return HS.sign("SHA384", ...)
end


function HS384.verify(...)
  return HS.verify("SHA384", ...)
end


local HS512 = {}


function HS512.sign(...)
  return HS.sign("SHA512", ...)
end


function HS512.verify(...)
  return HS.verify("SHA512", ...)
end


local RS256 = {}


function RS256.sign(...)
  return RS.sign("SHA256", ...)
end


function RS256.verify(...)
  return RS.verify("SHA256", ...)
end


local RS384 = {}


function RS384.sign(...)
  return RS.sign("SHA384", ...)
end

function RS384.verify(...)
  return RS.verify("SHA384", ...)
end


local RS512 = {}


function RS512.sign(...)
  return RS.sign("SHA512", ...)
end


function RS512.verify(...)
  return RS.verify("SHA512", ...)
end


local ES256 = {}


function ES256.sign(...)
  return ES.sign("SHA256", ...)
end


function ES256.verify(...)
  return ES.verify("SHA256", ...)
end


local ES384 = {}


function ES384.sign(...)
  return ES.sign("SHA384", ...)
end


function ES384.verify(...)
  return ES.verify("SHA384", ...)
end


local ES512 = {}


function ES512.sign(...)
  return ES.sign("SHA512", ...)
end


function ES512.verify(...)
  return ES.verify("SHA512", ...)
end


local PS256 = {}


function PS256.sign(...)
  return PS.sign("SHA256", ...)
end


function PS256.verify(...)
  return PS.verify("SHA256", ...)
end


local PS384 = {}


function PS384.sign(...)
  return PS.sign("SHA384", ...)
end


function PS384.verify(...)
  return PS.verify("SHA384", ...)
end


local PS512 = {}


function PS512.sign(...)
  return PS.sign("SHA512", ...)
end


function PS512.verify(...)
  return PS.verify("SHA512", ...)
end


local HMAC = {
  HS256 = HS256,
  HS384 = HS384,
  HS512 = HS512,
}


local SIGN = {
  HS256 = HS256.sign,
  HS384 = HS384.sign,
  HS512 = HS512.sign,
  RS256 = RS256.sign,
  RS384 = RS384.sign,
  RS512 = RS512.sign,
  ES256 = ES256.sign,
  ES384 = ES384.sign,
  ES512 = ES512.sign,
  PS256 = PS256.sign,
  PS384 = PS384.sign,
  PS512 = PS512.sign,
  EdDSA = EdDSA.sign,
}


-- if VERIFY is updated with new algoriths please update DPOP_SUPPORTED_ALGS too, when needed.
local VERIFY = {
  HS256 = HS256.verify,
  HS384 = HS384.verify,
  HS512 = HS512.verify,
  RS256 = RS256.verify,
  RS384 = RS384.verify,
  RS512 = RS512.verify,
  ES256 = ES256.verify,
  ES384 = ES384.verify,
  ES512 = ES512.verify,
  PS256 = PS256.verify,
  PS384 = PS384.verify,
  PS512 = PS512.verify,
  EdDSA = EdDSA.verify,
}

-- Note that we don't want symmetric hashing/signing algorithms enabled with DPoP
local DPOP_SUPPORTED_ALGS = "RS256 RS384 RS512 PS256 PS384 PS512 ES256 ES384 ES512 EdDSA"


local jwa = {
  HASH   = HASH,
  HMAC   = HMAC,
  SIGN   = SIGN,
  VERIFY = VERIFY,
  S256   = S256,
  S384   = S384,
  S512   = S512,
  HS256  = HS256,
  HS384  = HS384,
  HS512  = HS512,
  RS256  = RS256,
  RS384  = RS384,
  RS512  = RS512,
  ES256  = ES256,
  ES384  = ES384,
  ES512  = ES512,
  PS256  = PS256,
  PS384  = PS384,
  PS512  = PS512,
  EdDSA  = EdDSA,
}


function jwa.hash(alg, inp)
  local hash_alg = HASH[alg]
  if not hash_alg then
    return nil, "unsupported jwa hashing algorithm"
  end
  return hash_alg(inp)
end


function jwa.verify(alg, jwk, ...)
  if not alg then
    return nil, "jwa signature verification algorithm was not specified"
  end

  if jwk.alg then
    if jwk.alg ~= alg then
      return nil, "algorithm mismatch"
    end
  end

  local verify = VERIFY[alg]

  if not verify then
    return nil, "unsupported jwa signature verification algorithm was specified"
  end

  if type(jwk) ~= "table" then
    return nil, "invalid jwk was supplied for jwa signature verification"
  end

  return verify(jwk, ...)
end


function jwa.sign(alg, jwk, ...)
  if not alg then
    return nil, "jwa signing algorithm was not specified"
  end

  local sign = SIGN[alg]

  if not sign then
    return nil, "unsupported jwa signing algorithm was specified"
  end

  if type(jwk) ~= "table" then
    return nil, "invalid jwk was supplied for jwa signing"
  end

  return sign(jwk, ...)
end


function jwa.get_dpop_algs()
  return DPOP_SUPPORTED_ALGS
end


return jwa
