
local json_handler = require "kong.pdk.private.response.handler.json"

describe("response-hanlder", function()
  describe("json", function()
    it("match()", function()
      local handler = json_handler.new(nil)
      assert.is_true(handler:match("application", "json"))
      assert.is_true(handler:match("application", "jwk-set+json"))
    end)
  end)
end)
