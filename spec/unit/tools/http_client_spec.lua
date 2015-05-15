local cjson = require "cjson"
local http_client = require "kong.tools.http_client"

require "kong.tools.ngx_stub"

describe("HTTP Client", function()

  describe("GET", function()

    it("should send a valid GET request", function()
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

    it("should send a valid POST request with form encoded parameters", function()
      local response, status, headers = http_client.post("http://httpbin.org/post", {name = "Mark"}, {Custom = "pippo"})
      assert.are.equal(200, status)
      assert.truthy(headers)
      assert.truthy(response)
      local parsed_response = cjson.decode(response)
      assert.are.equal("Mark", parsed_response.form.name)
      assert.are.equal("pippo", parsed_response.headers.Custom)
    end)

    it("should send a valid POST request with a JSON body", function()
      local response, status, headers = http_client.post("http://httpbin.org/post",
        {name = "Mark"},
        {Custom = "pippo", ["content-type"]="application/json"}
      )
      assert.are.equal(200, status)
      assert.truthy(headers)
      assert.truthy(response)
      local parsed_response = cjson.decode(response)
      assert.are.equal("Mark", parsed_response.json.name)
      assert.are.equal("pippo", parsed_response.headers.Custom)
      assert.are.equal("application/json", headers["content-type"])
    end)

    it("should send a valid POST multipart request", function()
      local response, status, headers = http_client.post_multipart("http://httpbin.org/post", {name = "Mark"}, {Custom = "pippo"})
      assert.are.equal(200, status)
      assert.truthy(headers)
      assert.truthy(response)
      local parsed_response = cjson.decode(response)
      assert.are.equal("Mark", parsed_response.form.name)
      assert.are.equal("pippo", parsed_response.headers.Custom)
    end)

  end)

  describe("PUT", function()

    it("should send a valid PUT request", function()
      local response, status, headers = http_client.put("http://httpbin.org/put", {name="Mark"}, {["content-type"] = "application/json", Custom = "pippo"})
      assert.are.equal(200, status)
      assert.truthy(headers)
      assert.truthy(response)
      local parsed_response = cjson.decode(response)
      assert.are.equal("Mark", parsed_response.json.name)
      assert.are.equal("pippo", parsed_response.headers.Custom)
    end)

  end)

  describe("PATCH", function()

    it("should send a valid PUT request", function()
      local response, status, headers = http_client.patch("http://httpbin.org/patch", {name="Mark"}, {["content-type"] = "application/json", Custom = "pippo"})
      assert.are.equal(200, status)
      assert.truthy(headers)
      assert.truthy(response)
      local parsed_response = cjson.decode(response)
      assert.are.equal("Mark", parsed_response.json.name)
      assert.are.equal("pippo", parsed_response.headers.Custom)
    end)

  end)


  describe("DELETE", function()

    it("should send a valid DELETE request", function()
      local response, status, headers = http_client.delete("http://httpbin.org/delete", {name = "Mark"}, {Custom = "pippo"})
      assert.are.equal(200, status)
      assert.truthy(headers)
      assert.truthy(response)
      local parsed_response = cjson.decode(response)
      assert.are.equal("Mark", parsed_response.args.name)
      assert.are.equal("pippo", parsed_response.headers.Custom)
    end)

  end)

  describe("OPTIONS", function()

    it("should send a valid OPTIONS request", function()
      local response, status, headers = http_client.options("http://mockbin.com/request", {name = "Mark"}, {Custom = "pippo"})
      assert.are.equal(200, status)
      assert.truthy(headers)
      assert.truthy(response)
      local parsed_response = cjson.decode(response)
      assert.are.equal("Mark", parsed_response.queryString.name)
      assert.are.equal("pippo", parsed_response.headers.custom)
    end)

  end)

end)
