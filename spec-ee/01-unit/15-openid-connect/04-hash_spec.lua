-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local hash = require "kong.openid-connect.hash"

describe("Test hash", function ()
  it("correctly performs 'none' hash", function ()
    local s = "some_string"
    assert.equals(s, hash.none(s))
  end)

  it("correctly performs random hash 100 times", function()
    for _ = 1, 100 do
      local s = "some_string"
      local hashed = hash.random(s)
      local match = false
      for _,h in ipairs({ hash.S256(s), hash.S384(s), hash.S512(s) }) do
        match = match or h == hashed
      end
      assert.is_truthy(match)
    end
  end)

  it("correctly performs individual hash algorithms", function()
      local t = {
        S256 = {
          gruce = "YUxNp3z8X5yHznhV4mvBvLP8KBE78siR/vGwKhZsoUI="
        },
        S384 = {
          gruce = "YRwaSP/d4rElnimlrD103SCC5nOCr3mmNZtL7cNL6kSGiDXSUu4xZBR9LE" ..
                  "efQkdD"
        },
        S512 = {
          gruce = "tMDcdXATRsDbzl+ohpny5nxcQHBXpQIE4FaW/oOu8sb9bqGyIEl1qllWue" ..
                  "dmtgJrXUN4unC+AH/1k1fy6tL2Fw=="
        }
      }

      for alg, val in pairs(t) do
        for input, expected in pairs(val) do
          local hsh, err = ngx.encode_base64(hash[alg](input))
          assert.is_nil(err)
          assert.equals(expected, hsh)
        end
      end
  end)
end)
