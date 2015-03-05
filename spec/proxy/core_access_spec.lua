local utils = require "kong.tools.utils"
local cjson = require "cjson"

local kProxyURL = "http://localhost:8000/"
local kPostURL = kProxyURL.."/post"
local kGetURL = kProxyURL.."/get"

describe("Proxy API #proxy", function()

  describe("Invalid API", function()

    it("should return API not found when the API is missing", function()
      local response, status, headers = utils.get(kProxyURL)
      local body = cjson.decode(response)
      assert.are.equal(404, status)
      assert.are.equal("API not found", body.message)
    end)

  end)

  describe("Existing API", function()

    it("should return API found when the API has been created", function()
      local response, status, headers = utils.get(kGetURL, {}, {host = "test4.com"})
      assert.are.equal(200, status)
    end)

  end)
end)
