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
  --]]
  local large_string = string.rep("a", 1024 * 1024 * 1024) -- 1GB

  -- if bug exists, test will exit with 139 code (signal 11)
  local json = assert(cjson.encode({large_string = large_string}))
  assert(string.find(json, large_string, 1, true),
    "JSON string should contain the large string")
  end)
end)
