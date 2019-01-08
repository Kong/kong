local crypto = require "kong.plugins.basic-auth.crypto"

describe("Plugin: basic-auth (crypto)", function()
  it("encrypts a credential with consumer_id salt", function()
    local value = crypto.encrypt("id123", "pass123")
    assert.is_string(value)
    assert.equals(40, #value)
    assert.equals(crypto.encrypt("id123", "pass123"), crypto.encrypt("id123", "pass123"))
  end)

  it("substitutes empty string for password equal to nil", function()
    assert.equals(crypto.encrypt("id123"), crypto.encrypt("id123", ""))
  end)

  it("substitutes empty string for password equal to ngx.null", function()
    assert.equals(crypto.encrypt("id123"), crypto.encrypt("id123", ngx.null))
  end)
end)
