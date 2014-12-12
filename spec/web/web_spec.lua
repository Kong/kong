local utils = require "apenode.utils"
local cjson = require "cjson"
local kWebURL = "http://localhost:8001/"

describe("Web API #web", function()

  describe("/", function()
    it("should return the apenode version and a welcome message", function()
      local response, status, headers = utils.get(kWebURL)
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.truthy(body.version)
      assert.truthy(body.tagline)
    end)
  end)

end)
