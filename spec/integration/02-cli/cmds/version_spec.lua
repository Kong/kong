local IO = require "kong.tools.io"
local meta = require "kong.meta"
local stringy = require "stringy"
local spec_helper = require "spec.spec_helpers"

describe("CLI", function()
  it("should return the right version", function()
    local result = IO.os_execute(spec_helper.KONG_BIN.." version")
    assert.equal(meta._NAME.." version: "..meta._VERSION, stringy.strip(result))
  end)
end)
