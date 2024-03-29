-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local jwks = require "kong.openid-connect.jwks"
local jwa = require "kong.openid-connect.jwa"


describe("Test JSON Web Key Set(jwks)", function ()
    local t_jwks= jwks.new()

    for _, jwk in ipairs(t_jwks.keys) do
      local alg
      local inp = "payload"
      alg = jwk.alg

      it("to sign and verify correctly with [".. alg .. "]", function ()
        local sig, err = jwa.sign(alg, jwk, inp)
        assert.is_not_nil(sig)
        assert.is_nil(err)
        local ret, err = jwa.verify(alg, jwk, inp, sig)
        assert.is_not_nil(ret)
        assert.is_truthy(ret)
        assert.is_nil(err)
      end)
    end
end)
