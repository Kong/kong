-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local meta = require "kong.enterprise_edition.meta"


local strip = require("kong.tools.string").strip


describe("kong version", function()
  local package = tostring(meta.version)

  it("outputs Kong version", function()
    local _, _, stdout = assert(helpers.kong_exec("version"))
    assert.equal("Kong Enterprise " .. package, strip(stdout))
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
