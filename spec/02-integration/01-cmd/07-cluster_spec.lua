local helpers = require "spec.helpers"

local function exec(args)
  args = args or ""
  return helpers.execute(helpers.bin_path.." "..args)
end

describe("kong cluster", function()
  it("keygen", function()
    local ok, _, stdout, stderr = exec "cluster keygen"
    assert.True(ok)
    assert.equal("", stderr)
    assert.equal(26, stdout:len()) -- 24 + \r\n
  end)
end)
