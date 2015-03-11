local cjson = require "cjson"
local http_client = require "kong.tools.http_client"

describe("Http Client", function()

  describe("GET", function()

    it("should return a valid GET response", function()
      local response, status, headers = http_client.get("http://httpbin.org/get", {name = "Mark"}, {Custom = "pippo"})
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
      local response, status, headers = http_client.post("http://httpbin.org/post", {name = "Mark"}, {Custom = "pippo"})
      assert.are.equal(200, status)
      assert.truthy(headers)
      assert.truthy(response)
      local parsed_response = cjson.decode(response)
      assert.are.equal("Mark", parsed_response.form.name)
      assert.are.equal("pippo", parsed_response.headers.Custom)
    end)

  end)

  describe("PUT", function()

    it("should return a valid PUT response", function()
      local response, status, headers = http_client.put("http://httpbin.org/put", {name="Mark"}, {Custom = "pippo"})
      assert.are.equal(200, status)
      assert.truthy(headers)
      assert.truthy(response)
      local parsed_response = cjson.decode(response)
      assert.are.equal("Mark", parsed_response.json.name)
      assert.are.equal("pippo", parsed_response.headers.Custom)
    end)

  end)

  describe("DELETE", function()

    it("should return a valid DELETE response", function()
      local response, status, headers = http_client.delete("http://httpbin.org/delete", {name = "Mark"}, {Custom = "pippo"})
      assert.are.equal(200, status)
      assert.truthy(headers)
      assert.truthy(response)
      local parsed_response = cjson.decode(response)
      assert.are.equal("Mark", parsed_response.args.name)
      assert.are.equal("pippo", parsed_response.headers.Custom)
    end)

  end)

end)