local helpers = require "spec.helpers"
local meta = require "kong.meta"


local strip = require("kong.tools.string").strip


describe("kong version", function()
  it("outputs Kong version", function()
    local _, _, stdout = assert(helpers.kong_exec("version"))
    assert.equal(meta._VERSION, strip(stdout))
  end)
  it("--all outputs all deps versions", function()
    local _, _, stdout = assert(helpers.kong_exec("version -a"))
    local escaped_version = string.gsub(meta._VERSION, "%-", "%%-")
    assert.matches([[
Kong: ]] .. escaped_version .. [[

ngx_lua: %d+
nginx: %d+
Lua: .*
]], stdout)
  end)
end)
