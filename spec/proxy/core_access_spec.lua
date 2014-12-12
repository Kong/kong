require "spec.dao.sqlite.configuration"
local dao_factory = require "apenode.dao.sqlite"

local utils = require "apenode.utils"
local cjson = require "cjson"
local kProxyURL = "http://localhost:8000/"
local kWebURL = "http://localhost:8001/"

describe("Proxy API #proxy", function()

  describe("Invalid API", function()
    it("should return API not found when the API is missing", function()
      local response, status, headers = utils.get(kProxyURL)
      local body = cjson.decode(response)
      assert.are.equal(404, status)
      assert.are.equal("API not found", body.message)
    end)
  end)

  describe("Existing API, but invalid query authentication credentials", function ()

    setup(function()
      dao_factory.populate(true)
    end)

    teardown(function()
      dao_factory.drop()
    end)

    it("should return API found when the API has been created", function()
      local response, status, headers = utils.get(kProxyURL .. "get", {}, {host = "test.com"})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Your authentication credentials are invalid", body.message)
    end)
    it("should return invalid credentials when the credential value is wrong", function()
      local response, status, headers = utils.get(kProxyURL .. "get", {apikey = "asd"}, {host = "test.com"})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Your authentication credentials are invalid", body.message)
    end)
    it("should return invalid credentials when the credential parameter name is wrong", function()
      local response, status, headers = utils.get(kProxyURL .. "get", {apikey123 = "apikey123"}, {host = "test.com"})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Your authentication credentials are invalid", body.message)
    end)
    it("should pass", function()
      local response, status, headers = utils.get(kProxyURL .. "get", {apikey = "apikey123"}, {host = "test.com"})
      assert.are.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.are.equal("apikey123", parsed_response.args.apikey)
    end)
  end)

end)
