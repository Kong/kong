local spec_helper = require "spec.spec_helpers"
local constants = require "kong.constants"
local stringy = require "stringy"
local IO = require "kong.tools.io"

describe("CLI", function()

  it("should return the right version", function()
    local result = IO.os_execute(spec_helper.KONG_BIN.." version")
    assert.are.same("Kong version: "..constants.VERSION, stringy.strip(result))
  end)

end)
