local pl_stringx = require "pl.stringx"
local helpers = require "spec.helpers"
local meta = require "kong.meta"

describe("kong version", function()
  it("outputs Kong version", function()
    local _, stderr, stdout = helpers.kong_exec("version")
    assert.equal("", stderr)
    assert.equal(meta._VERSION, pl_stringx.strip(stdout))
  end)
  it("--all outputs all deps versions", function()
    local _, stderr, stdout = helpers.kong_exec("version -a")
    assert.equal("", stderr)
    assert.matches([[
Kong: %d+%.%d+%.%d+
ngx_lua: %d+
nginx: %d+
Lua: .*
]], stdout)
  end)
end)
