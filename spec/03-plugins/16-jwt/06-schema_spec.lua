-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local schema_def = require "kong.plugins.jwt.schema"
local v = require("spec.helpers").validate_plugin_config_schema


describe("Plugin: jwt (schema)", function()
  it("validates 'maximum_expiration'", function()
    local ok, err = v({
      maximum_expiration = 60,
      claims_to_verify = { "exp", "nbf" },
    }, schema_def)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  describe("errors", function()
    it("when 'maximum_expiration' is negative", function()
      local ok, err = v({
        maximum_expiration = -1,
        claims_to_verify = { "exp", "nbf" },
      }, schema_def)

      assert.is_falsy(ok)
      assert.same({
        maximum_expiration = "value should be between 0 and 31536000"
      }, err.config)

      local ok, err = v({
        maximum_expiration = -1,
        claims_to_verify = { "nbf" },
      }, schema_def)

      assert.is_falsy(ok)
      assert.same({
        maximum_expiration = "value should be between 0 and 31536000"
      }, err.config)
    end)

    it("when 'maximum_expiration' is specified without 'exp' in 'claims_to_verify'", function()
      local ok, err = v({
        maximum_expiration = 60,
        claims_to_verify = { "nbf" },
      }, schema_def)

      assert.is_falsy(ok)
      assert.equals("expected to contain: exp", err.config.claims_to_verify)
    end)
  end)
end)
