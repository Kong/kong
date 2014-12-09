local utils = require "apenode.utils"
local cjson = require "cjson"
local kWebURL = "http://localhost:8000/"

describe("Proxy API #proxy", function()
  describe("/", function()

    it("should return API not found", function()
      utils.get(kWebURL, function(status, bodyStr)
        local body = cjson.decode(bodyStr)
        assert.are.equal(404, status)
        assert.are.equal("API not found", body.message)
      end)
    end)

  end)
end)
