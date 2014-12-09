local utils = require "apenode.utils"
local cjson = require "cjson"
local kWebURL = "http://localhost:8001/"

describe("Proxy API #web", function()
  describe("/", function()

    it("should return the apenode version and a welcome message", function()
      utils.get(kWebURL, function(status, bodyStr)
        local body = cjson.decode(bodyStr)
        assert.are.equal(200, status)
        assert.truthy(body.version)
        assert.truthy(body.tagline)
      end)
    end)

  end)
end)
