-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local sx = require("pl.stringx")

describe("testing directory", function()
  it("does not have extra lua files that are not going to be ran", function()
    local command = 'ls -R spec-ee/ | grep "lua$"'
    local f = io.popen(command)
    local l = sx.splitlines(f:read("*a"))
    f:close()

    local wrong_filename = {}
    for _, f in ipairs(l) do
      if f == "helpers.lua" or f == "06-proxies-spec.lua"  then
        _ = 0 -- all cool
      elseif f:find("_spec.lua$") then
        _ = 0 -- all cool
      else
        table.insert(wrong_filename, f)
      end

      assert.equals(0, #wrong_filename)
    end
  end)

end)
