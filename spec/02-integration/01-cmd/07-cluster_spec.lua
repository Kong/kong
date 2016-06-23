local helpers = require "spec.helpers"

describe("kong cluster", function()
  it("keygen", function()
    local _, stderr, stdout = helpers.kong_exec "cluster keygen"
    assert.equal("", stderr)
    assert.equal(26, stdout:len()) -- 24 + \r\n
  end)
end)
