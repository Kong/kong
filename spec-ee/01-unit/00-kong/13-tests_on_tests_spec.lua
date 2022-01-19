-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local sx = require("pl.stringx")

describe("testing directory", function()
  it("does not have extra lua files that are not going to be ran", function()
    local command = [[find spec-ee/ -type f -name '*.lua']]
    local fh = io.popen(command)
    local l = sx.splitlines(fh:read("*a"))
    fh:close()

    local wrong_filename = {}
    for _, f in ipairs(l) do
      if not f:find("^spec%-ee/fixtures/")
         and not f:find("/helpers.lua$")
         and not f:find("/06%-proxies%-spec.lua$")
         and not f:find("_spec.lua$")
      then
        table.insert(wrong_filename, f)
      end
    end

    assert.same({}, wrong_filename)
  end)

end)
