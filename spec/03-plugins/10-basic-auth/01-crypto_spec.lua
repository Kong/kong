-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local crypto = require "kong.plugins.basic-auth.crypto"

describe("Plugin: basic-auth (crypto)", function()
  it("hashs a credential with consumer_id salt", function()
    local value = crypto.hash("id123", "pass123")
    assert.is_string(value)
    assert.equals(40, #value)
    assert.equals(crypto.hash("id123", "pass123"), crypto.hash("id123", "pass123"))
  end)

  it("substitutes empty string for password equal to nil", function()
    assert.equals(crypto.hash("id123"), crypto.hash("id123", ""))
  end)

  it("substitutes empty string for password equal to ngx.null", function()
    assert.equals(crypto.hash("id123"), crypto.hash("id123", ngx.null))
  end)
end)

describe("Plugin: basic-auth (crypto: #fips)", function()
  before_each(function()
    _G.kong = {
      configuration = {
        fips = true,
      }
    }
  end)

  after_each(function()
    _G.kong = nil
  end)

  it("hashs a credential with consumer_id salt with sha256", function()
    local value = crypto.hash("id123", "pass123")
    assert.is_string(value)
    assert.equals(64, #value)
    assert.equals(crypto.hash("id123", "pass123"), crypto.hash("id123", "pass123"))
  end)

  it("FIPS mode can cross verify", function()
    local value, err = crypto.hash("id123", "pass123")
    assert.is_nil(err)
    assert.is_string(value)
    assert.truthy(crypto.verify("id123", "pass123", value))
  end)
end)
