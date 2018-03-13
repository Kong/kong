local crypto = require "kong.plugins.basic-auth.crypto"

describe("Plugin: basic-auth (crypto)", function()
  it("encrypts a credential with consumer_id salt", function()
    local credential = {
      consumer_id = "id123",
      password = "pass123"
    }

    local value = crypto.encrypt(credential)
    assert.is_string(value)
    assert.equals(40, #value)
    assert.equals(crypto.encrypt(credential), crypto.encrypt(credential))
  end)

  it("substitutes empty string for nil password in salt", function()
    local credential = {
      consumer_id = "id123"
    }

    local credential2 = {
      consumer_id = "id123",
      password = ""
    }
    assert.equals(crypto.encrypt(credential), crypto.encrypt(credential2))
  end)
end)
