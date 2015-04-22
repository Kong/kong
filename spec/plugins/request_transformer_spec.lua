local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"

STUB_GET_URL = spec_helper.STUB_GET_URL
STUB_POST_URL = spec_helper.STUB_POST_URL

describe("Request Transformer Plugin #proxy", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
    spec_helper.reset_db()
  end)

  describe("Test adding parameters", function()

    it("should add new headers", function()
      local response, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test5.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.are.equal("true", body.headers["x-added"])
      assert.are.equal("true", body.headers["x-added2"])
    end)

    it("should add new parameters on POST", function()
      local response, status, headers = http_client.post(STUB_POST_URL, {}, {host = "test5.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.are.equal("newvalue", body.postData.params["newformparam"])
    end)

    it("should add new parameters on POST when existing params exist", function()
      local response, status, headers = http_client.post(STUB_POST_URL, { hello = "world" }, {host = "test5.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.are.equal("world", body.postData.params["hello"])
      assert.are.equal("newvalue", body.postData.params["newformparam"])
    end)

    it("should add new parameters on multipart POST", function()
      local response, status, headers = http_client.post_multipart(STUB_POST_URL, {}, {host = "test5.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.are.equal("newvalue", body.postData.params["newformparam"])
    end)

    it("should add new parameters on multipart POST when existing params exist", function()
      local response, status, headers = http_client.post_multipart(STUB_POST_URL, { hello = "world" }, {host = "test5.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.are.equal("world", body.postData.params["hello"])
      assert.are.equal("newvalue", body.postData.params["newformparam"])
    end)

    it("should add new parameters on GET", function()
      local response, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test5.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.are.equal("value", body.queryString["newparam"])
    end)

  end)

  describe("Test removing parameters", function()

    it("should remove a header", function()
      local response, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test5.com", ["x-to-remove"] = "true"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.falsy(body.headers["x-to-remove"])
    end)

    it("should remove parameters on POST", function()
      local response, status, headers = http_client.post(STUB_POST_URL, {["toremoveform"] = "yes", ["nottoremove"] = "yes"}, {host = "test5.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.falsy(body.postData.params["toremoveform"])
      assert.are.same("yes", body.postData.params["nottoremove"])
    end)

    it("should remove parameters on multipart POST", function()
      local response, status, headers = http_client.post_multipart(STUB_POST_URL, {["toremoveform"] = "yes", ["nottoremove"] = "yes"}, {host = "test5.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.falsy(body.postData.params["toremoveform"])
      assert.are.same("yes", body.postData.params["nottoremove"])
    end)

    it("should remove parameters on GET", function()
      local response, status, headers = http_client.get(STUB_GET_URL, {["toremovequery"] = "yes", ["nottoremove"] = "yes"}, {host = "test5.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.falsy(body.queryString["toremovequery"])
      assert.are.equal("yes", body.queryString["nottoremove"])
    end)

  end)
end)
