-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local secret_impl = require "kong.plugins.oauth2.secret"


describe("Plugin: oauth2 (secret)", function()
  describe("PBKDF", function()

    local static_key = "$pbkdf2-sha512$i=10000,l=32$YSBsaXR0ZSBiaXQsIGp1c3QgYSBsaXR0bGUgYml0$z6ysNworexAhDELywIDi0ba0B0T7F/MBZ6Ige9lWRYI"

    it("sanity test", function()
      -- Note: to pass test in FIPS mode, salt length has to be 16 bytes or more
      local derived, err = secret_impl.hash("tofu", { salt = "a litte bit, just a little bit" })
      assert.is_nil(err)
      assert.same(static_key, derived)
    end)

    it("uses random salt by default", function()
      local derived, err = secret_impl.hash("tofu")
      assert.is_nil(err)
      assert.not_same(static_key, derived)
    end)

    it("verifies correctly", function()
      local derived, err = secret_impl.hash("tofu")
      assert.is_nil(err)

      local ok, err = secret_impl.verify("tofu", derived)
      assert.is_nil(err)
      assert.is_truthy(ok)

      local ok, err = secret_impl.verify("tofu", static_key)
      assert.is_nil(err)
      assert.is_truthy(ok)


      local derived2, err = secret_impl.hash("bun")
      assert.is_nil(err)

      local ok, err = secret_impl.verify("tofu", derived2)
      assert.is_nil(err)
      assert.is_falsy(ok)
    end)

  end)
end)
