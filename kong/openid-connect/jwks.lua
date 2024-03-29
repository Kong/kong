-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local random    = require "kong.openid-connect.random"
local codec     = require "kong.openid-connect.codec"
local pkey      = require "resty.openssl.pkey"
local is_fips   = require "resty.openssl".get_fips_mode

local ES_CURVES = {
  ES256 = "P-256",
  ES384 = "P-384",
  ES512 = "P-521",
}

local EC_CURVES_MAP = {
  ["P-256"] = "prime256v1",
  ["P-384"] = "secp384r1",
  ["P-521"] = "secp521r1",
}

local HSKEYSIZES = {
  HS256 = 32,
  HS384 = 48,
  HS512 = 64,
}


local base64url  = codec.base64url
local json       = codec.json
local fmt        = string.format

local function hs_jwk(jwk)
  jwk = jwk or {
    kty = "oct",
    use = "sig",
    alg = "HS256"
  }

  local ks = HSKEYSIZES[jwk.alg] or 32
  local k, err = base64url.encode(random(ks))
  if not k then
    return nil, err
  end

  local kid
  kid, err = base64url.encode(random(32))
  if not kid then
    return nil, err
  end

  jwk.kty = jwk.kty or "oct"
  jwk.alg = jwk.alg or "HS256"
  jwk.use = jwk.use or "sig"

  jwk.kid = kid
  jwk.k = k

  return jwk
end


local function validate_set_parameters(keypair, expected_fields, jwk, to_binary)
  local keypair_params, err = keypair:get_parameters()
  if not keypair_params then
    return nil, err
  end

  for jwk_param_n, keypair_param_n in pairs(expected_fields) do
    local param_value = keypair_params[keypair_param_n]
    if not param_value then
      return nil, fmt(
        "jwk parameters validation failed: missing field %s",
        keypair_param_n
      )
    end

    local encoded_p
    if to_binary then
      param_value = param_value:to_binary()
    end
    encoded_p, err = base64url.encode(param_value)
    if not encoded_p then
      return nil, err
    end

    jwk[jwk_param_n] = encoded_p
  end

  return jwk
end


local function rs_jwk(jwk)
  local rs_parameters = {
    e = "e",
    n = "n",
    d = "d",
    p = "p",
    q = "q",
    dp = "dmp1",
    dq = "dmq1",
    qi = "iqmp",
  }

  jwk = jwk or {
    kty = "RSA",
    use = "sig",
    alg = "RS256",
  }

  local keypair, err = pkey.new({
    type = 'RSA',
    bits = 2048,
    exp = 65537
  })
  if not keypair then
    return nil, err
  end

  jwk, err = validate_set_parameters(keypair, rs_parameters, jwk, true)
  if not jwk then
    return nil, err
  end

  local kid
  kid, err = base64url.encode(random(32))
  if not kid then
    return nil, err
  end
  jwk.kid = kid

  jwk.kty = jwk.kty or "RSA"
  jwk.alg = jwk.alg or "RS256"
  jwk.use = jwk.use or "sig"

  return jwk
end


local function es_jwk(jwk)
  local es_parameters = {
    x = "x",
    y = "y",
    d = "private",
  }

  jwk = jwk or {
    kty = "EC",
    use = "sig",
  }

  jwk.crv = jwk.crv or ES_CURVES[jwk.alg] or "P-256"
  local ec_curve = EC_CURVES_MAP[jwk.crv]

  local keypair, err = pkey.new({
    type = "EC",
    curve = ec_curve
  })

  if not keypair then
    return nil, err
  end

  jwk, err = validate_set_parameters(keypair, es_parameters, jwk, true)
  if not jwk then
    return nil, err
  end

  local kid
  kid, err = base64url.encode(random(32))
  if not kid then
    return nil, err
  end
  jwk.kid = kid

  jwk.kty = jwk.kty or "EC"
  jwk.use = jwk.use or "sig"

  return jwk
end


local function ed_jwk(jwk)
  local ed_parameters = {
    x = "public",
    d = "private",
  }

  jwk = jwk or {
    kty = "OKP",
    use = "sig",
    crv = "Ed25519",
  }

  jwk.crv = jwk.crv or "Ed25519"

  local keypair, err = pkey.new({
    type = jwk.crv
  })
  if not keypair then
    return nil, err
  end

  jwk, err = validate_set_parameters(keypair, ed_parameters, jwk, false)
  if not jwk then
    return nil, err
  end

  local kid
  kid, err = base64url.encode(random(32))
  if not kid then
    return nil, err
  end
  jwk.kid = kid

  jwk.kty = jwk.kty or "OKP"
  jwk.use = jwk.use or "sig"

  return jwk
end


local jwks = {}


function jwks.new(options)
  options = options or {}

  local hs256, err = hs_jwk({
    alg = "HS256"
  })

  if not hs256 then
    return nil, err
  end

  local hs384
  hs384, err = hs_jwk({
    alg = "HS384"
  })

  if not hs384 then
    return nil, err
  end

  local hs512
  hs512, err = hs_jwk({
    alg = "HS512"
  })

  if not hs512 then
    return nil, err
  end

  local rs256
  rs256, err = rs_jwk({
    alg = "RS256"
  })

  if not rs256 then
    return nil, err
  end

  local rs384
  rs384, err = rs_jwk({
    alg = "RS384"
  })

  if not rs384 then
    return nil, err
  end

  local rs512
  rs512, err = rs_jwk({
    alg = "RS512"
  })

  if not rs512 then
    return nil, err
  end

  local ps256
  ps256, err = rs_jwk({
    alg = "PS256"
  })

  if not ps256 then
    return nil, err
  end

  local ps384
  ps384, err = rs_jwk({
    alg = "PS384"
  })

  if not ps384 then
    return nil, err
  end

  local ps512
  ps512, err = rs_jwk({
    alg = "PS512"
  })

  if not ps512 then
    return nil, err
  end

  local es256
  es256, err = es_jwk({
    alg = "ES256"
  })

  if not es256 then
    return nil, err
  end

  local es384
  es384, err = es_jwk({
    alg = "ES384"
  })

  if not es384 then
    return nil, err
  end

  local es512
  es512, err = es_jwk({
    alg = "ES512"
  })

  if not es512 then
    return nil, err
  end

  local ed25519
  ed25519, err = ed_jwk({
    alg = "EdDSA",
    crv = "Ed25519",
  })

  if not ed25519 then
    return nil, err
  end

  local keys = {
    hs256,
    hs384,
    hs512,
    rs256,
    rs384,
    rs512,
    ps256,
    ps384,
    ps512,
    es256,
    es384,
    es512,
    ed25519,
  }

  -- These algs are not supported by BoringSSL: add them when FIPS is disabled.
  -- See: https://commondatastorage.googleapis.com/chromium-boringssl-docs/evp.h.html#EVP_PKEY_ED448
  -- Alternatively, we could check the value of `openssl.version.version_text`
  if not is_fips() then
    local ed448
    ed448, err = ed_jwk({
      alg = "EdDSA",
      crv = "Ed448",
    })

    if not ed448 then
      return nil, err
    end

    keys[#keys + 1] = ed448
  end

  if options.unwrap ~= true then
    keys = {
      keys = keys
    }
  end

  if options.json == true then
    keys, err = json.encode(keys)
    if not keys then
      return nil, err
    end
  end

  return keys
end


return jwks
