-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local PLUGIN_NAME = "openid-connect"

describe(PLUGIN_NAME .. ": (schema)", function()

  describe("openid-connect.claims", function()
    local claim_module = require("kong.plugins." .. PLUGIN_NAME .. ".claims")

    it("is expired higher `now`", function()
      local expired, err = claim_module.token_is_expired(1, 2)
      assert.is_true(expired)
      assert.is_equal(err, "token has expired")
    end)

    it("is not expired", function()
      local expired, err = claim_module.token_is_expired(2, 1)
      assert.is_falsy(expired)
      assert.is_nil(err)
    end)

    it("is expired eq values", function()
      local expired, err = claim_module.token_is_expired(1, 1)
      assert.is_true(expired)
      assert.is_equal(err, "token has expired")
    end)

    it("invalid type input exp", function()
      local expired, err = claim_module.token_is_expired("1", 1)
      assert.is_true(expired)
      assert.is_equal(err, "exp must be a number")
    end)

    it("invalid type input now", function()
      local expired, err = claim_module.token_is_expired(1, "1")
      assert.is_true(expired)
      assert.is_equal(err, "now must be a number")
    end)

    it("invalid value input now", function()
      local expired, err = claim_module.token_is_expired(1, -1)
      assert.is_true(expired)
      assert.is_equal(err, "now must be greater than 0")
    end)

    it("invalid value input exp", function()
      local expired, err = claim_module.token_is_expired(-1, 1)
      assert.is_true(expired)
      assert.is_equal(err, "exp must be greater than 0")
    end)
  end)
end)
