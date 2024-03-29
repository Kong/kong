-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local VALIDATION = {
  HS = {
    s = {
      req = {
        k = "hs shared secret"
      }, opt = {}
    }
  },
  RSA = {
    s = {
      req = {
        n = "modulus",
        e = "exponent",
        d = "secret exponent",
        p = "factor p",
        q = "factor q",
      },
      opt = { "dp", "dq", "qi" }
    },
    v = {
      req = {
        n = "modulus",
        e = "exponent",
      },
      opt = {}
    }
  },
  EC = {
    s = {
      req = {
        x = "ecdsa x coordinate",
        y = "ecdsa y coordinate",
        crv = "ecdsa curve",
        d = "ecdsa ecc private key",
      },
      opt = {}
    },
    v = {
      req = {
        crv = "ecdsa curve",
        x = "ecdsa x coordinate",
        y = "ecdsa y coordinate",
      },
      opt = {}
    }
  },
  OKP = {
    s = {
      req = {
        crv = "eddsa curve",
        d = "eddsa ecc private key",
      },
      opt = { "x" }
    },
    v = {
      req = {
        crv = "eddsa curve",
        x = "eddsa x coordinate",
      },
      opt = {}
    }
  },
}

local JWK = {}

JWK.__index = JWK

function JWK.validate(scheme, op, jwk)
  local req_keys = VALIDATION[scheme][op]["req"]
  local opt_keys = VALIDATION[scheme][op]["opt"]
  local v_jwk = {}

  for k, name in pairs(req_keys) do
    if not jwk[k] then
      return nil, name .. " was not specified"
    end
    v_jwk[k] = jwk[k]
  end
  for _, k in ipairs(opt_keys) do
    v_jwk[k] = jwk[k]
  end

  return v_jwk
end

return JWK
