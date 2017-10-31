local pl_stringx = require "pl.stringx"
local helpers = require "spec.helpers"
local ee_meta = require "kong.enterprise_edition.meta"

describe("kong version", function()
  local package = tostring(ee_meta.versions.package)

  it("outputs Kong version", function()
    local _, _, stdout = assert(helpers.kong_exec("version"))
    assert.equal("Kong Enterprise " .. package, pl_stringx.strip(stdout))
  end)
  it("--all outputs all deps versions", function()
    local _, _, stdout = assert(helpers.kong_exec("version -a"))
    assert.matches([[
Kong Enterprise: ]] .. package:gsub("-", "%%-") .. [[

ngx_lua: %d+
nginx: %d+
Lua: .*
]], stdout)
  end)
end)
