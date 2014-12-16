local utils = require "apenode.utils"
local cjson = require "cjson"

describe("Utils #utils", function()

  describe("GET", function()
    it("should return a valid GET response", function()
      local response, status, headers = utils.get("http://httpbin.org/get", {name = "Mark"}, {Custom = "pippo"})
      assert.are.equal(200, status)
      assert.truthy(headers)
      assert.truthy(response)
      local parsed_response = cjson.decode(response)
      assert.are.equal("Mark", parsed_response.args.name)
      assert.are.equal("pippo", parsed_response.headers.Custom)
    end)
  end)

  describe("POST", function()
    it("should return a valid POST response", function()
      local response, status, headers = utils.post("http://httpbin.org/post", {name = "Mark"}, {Custom = "pippo"})
      assert.are.equal(200, status)
      assert.truthy(headers)
      assert.truthy(response)
      local parsed_response = cjson.decode(response)
      assert.are.equal("Mark", parsed_response.form.name)
      assert.are.equal("pippo", parsed_response.headers.Custom)
    end)
  end)

end)
