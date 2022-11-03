-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local fmt = string.format

for _, strategy in helpers.all_strategies() do
  describe("db.jwks #" .. strategy, function()
    local init_jwk_set
    local init_jwk
    local bp, db

    lazy_setup(function()
      helpers.setenv("JWK_SECRET", "wowsuchsecret")

      bp, db = helpers.get_db_utils(strategy ~= "off" and strategy or nil, {
        "vaults",
        "jwks",
        "jwk_sets"
      })

      init_jwk_set = assert(bp.jwk_sets:insert {
        name = "testset",
      })
      init_jwk = assert(bp.jwks:insert {
        name = "test",
        set = init_jwk_set,
        kid = "123",
        jwk = { kid = "123" }
      })
    end)

    before_each(function()
    end)

    after_each(function()
      db:truncate("jwks")
      db:truncate("jwk-sets")
    end)

    lazy_teardown(function()
    end)

    it(":select returns an item", function()
      local jwk_o, err = db.jwks:select({ id = init_jwk.id })
      assert.same('123', jwk_o.kid)
      assert.same('123', jwk_o.jwk.kid)
      assert.is_nil(err)
    end)

    it(":insert handles private field that is not a reference", function()
      local noref, insert_err = db.jwks:insert {
        name = "vault references",
        set = init_jwk_set,
        kid = "1",
        jwk = { kid = "1", d = "no-ref" }
      }
      assert.is_nil(insert_err)
      assert.same("1", noref.kid)
      assert.same("no-ref", noref.jwk.d)
    end)

    for _, priv in ipairs{"d", "p", "q", "dp", "dq", "qi", "oth"} do
      it(fmt(":insert handles field %s when passing a vault reference", priv), function()
        local reference = "{vault://env/jwk_secret}"
        local ref, insert_err = db.jwks:insert {
          name = "vault references",
          set = init_jwk_set,
          kid = "1",
          jwk = { kid = "1", [priv] = reference }
        }
        assert.is_nil(insert_err)
        assert.same(ref.jwk["$refs"][priv], reference)
        assert.same(ref.jwk[priv], "wowsuchsecret")
      end)
    end
  end)
end
