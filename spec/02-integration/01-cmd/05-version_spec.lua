local pl_stringx = require "pl.stringx"
local helpers = require "spec.helpers"
local meta = require "kong.meta"

describe("kong version", function()
  it("outputs Kong version", function()
    local _, _, stdout = assert(helpers.kong_exec("version"))
    assert.equal(meta._VERSION, pl_stringx.strip(stdout))
  end)
  it("--all outputs all deps versions", function()
    local _, _, stdout = assert(helpers.kong_exec("version -a"))
    assert.matches([[
Kong: ]] .. meta._VERSION .. [[

ngx_lua: %d+
nginx: %d+
Lua: .*
]], stdout)
  end)
end)
