-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
local helpers = require "spec.helpers"
local meta = require "kong.meta"

describe("kong cli verbose output", function()
  it("--vv outputs debug level log", function()
    local _, stderr, stdout = assert(helpers.kong_exec("version --vv"))
    -- globalpatches debug log will be printed by upper level resty command that runs kong.cmd
    assert.matches("installing the globalpatches", stderr)
    assert.matches("Kong: " .. meta._VERSION, stdout)
  end)
end)
