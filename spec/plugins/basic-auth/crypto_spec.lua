local crypto = require "kong.plugins.basic-auth.crypto"

describe("Basic Authentication Crypt", function()
  it("should encrypt", function()
    local credential = {
      consumer_id = "id123",
      password = "pass123"
    }

    local value = crypto.encrypt(credential)
    assert.truthy(value)
    assert.equals(40, string.len(value))
    assert.equals(crypto.encrypt(credential), crypto.encrypt(credential))
  end)
end)