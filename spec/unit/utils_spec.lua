local utils = require "kong.tools.utils"
local cjson = require "cjson"

describe("Utils #utils", function()

  describe("Cache", function()
    it("should return a valid API cache key", function()
      assert.are.equal("apis/httpbin.org", utils.cache_api_key("httpbin.org"))
    end)
    it("should return a valid PLUGIN cache key", function()
      assert.are.equal("plugins/authentication/api123/app123", utils.cache_plugin_key("authentication", "api123", "app123"))
    end)
  end)

  describe("HTTP", function()
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

    describe("PUT", function()
      it("should return a valid PUT response", function()
        local response, status, headers = utils.put("http://httpbin.org/put", {name="Mark"}, {Custom = "pippo"})
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
      local response, status, headers = utils.delete("http://httpbin.org/delete", {name = "Mark"}, {Custom = "pippo"})
      assert.are.equal(200, status)
      assert.truthy(headers)
      assert.truthy(response)
      local parsed_response = cjson.decode(response)
      assert.are.equal("Mark", parsed_response.args.name)
      assert.are.equal("pippo", parsed_response.headers.Custom)
      end)
    end)
  end)

  describe("tables", function()

    describe("#is_empty()", function()

      it("should return true for empty table, false otherwise", function()
        assert.True(utils.is_empty({}))
        assert.is_not_true(utils.is_empty({ foo = "bar" }))
        assert.is_not_true(utils.is_empty({ "foo", "bar" }))
      end)

    end)

    describe("#table_size()", function()

      it("should return the size of a table", function()
        assert.are.same(0, utils.table_size({}))
        assert.are.same(1, utils.table_size({ foo = "bar" }))
        assert.are.same(2, utils.table_size({ foo = "bar", bar = "baz" }))
        assert.are.same(2, utils.table_size({ "foo", "bar" }))
      end)

    end)

    describe("#reverse_table()", function()

      it("should reverse an array", function()
        local arr = { "a", "b", "c", "d" }
        assert.are.same({ "d", "c", "b", "a" }, utils.reverse_table(arr))
      end)

    end)
  end)
end)
