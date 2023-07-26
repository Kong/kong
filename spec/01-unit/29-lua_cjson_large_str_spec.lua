-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require("cjson.safe")

describe("cjson", function()
  it("should encode large JSON string correctly", function()
  --[[
    This test is to ensure that `cjson.encode()`
    can encode large JSON strings correctly,
    the JSON string is the string element in JSON representation,
    not the JSON string serialized from a Object.

    The bug is caused by the overflow of the `int`,
    and it will casue the signal 11 when writing the string to buffer.

    On EE, I changed the string size to 500MB
    as our self-hosted runner has less memory than the GitHub-hosted runner.
  --]]
  local large_string = string.rep("a", 1024 * 1024 * 500) -- 500MB

  -- if bug exists, test will exit with 139 code (signal 11)
  local json = assert(cjson.encode({large_string = large_string}))
  assert(string.find(json, large_string, 1, true),
    "JSON string should contain the large string")
  end)
end)
