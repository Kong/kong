local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"

local STUB_GET_URL = spec_helper.STUB_GET_URL
local STUB_POST_URL = spec_helper.STUB_POST_URL

describe("Request Transformer", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        {name = "tests-request-transformer-1", request_host = "test1.com", upstream_url = "http://mockbin.com"},
        {name = "tests-request-transformer-2", request_host = "test2.com", upstream_url = "http://httpbin.org"}
      },
      plugin = {
        {
          name = "request-transformer",
          config = {
            add = {
              headers = {"x-added:true", "x-added2:true" },
              querystring = {"newparam:value"},
              form = {"newformparam:newvalue"},
              json = {"newjsonparam:newvalue"}
            },
            remove = {
              headers = {"x-to-remove"},
              querystring = {"toremovequery"},
              form = {"toremoveform"},
              json = {"toremovejson"}
            }
          },
          __api = 1
        },
        {
          name = "request-transformer",
          config = {
            add = {
              headers = {"host:mark"}
            }
          },
          __api = 2
        }
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("Test adding parameters", function()
    it("should add new headers", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "test1.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.are.equal("true", body.headers["x-added"])
      assert.are.equal("true", body.headers["x-added2"])
    end)
    it("should add new parameters on POST", function()
      local response, status = http_client.post(STUB_POST_URL, {}, {host = "test1.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.are.equal("newvalue", body.postData.params["newformparam"])
    end)
    it("should add new parameters on POST when existing params exist", function()
      local response, status = http_client.post(STUB_POST_URL, {hello = "world"}, {host = "test1.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.are.equal("world", body.postData.params["hello"])
      assert.are.equal("newvalue", body.postData.params["newformparam"])
    end)
    it("should add new parameters on multipart POST", function()
      local response, status = http_client.post_multipart(STUB_POST_URL, {}, {host = "test1.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.are.equal("newvalue", body.postData.params["newformparam"])
    end)
    it("should add new parameters on multipart POST when existing params exist", function()
      local response, status = http_client.post_multipart(STUB_POST_URL, {hello = "world"}, {host = "test1.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.are.equal("world", body.postData.params["hello"])
      assert.are.equal("newvalue", body.postData.params["newformparam"])
    end)
    it("should add new paramters on json POST", function()
      local response, status = http_client.post(STUB_POST_URL, {}, {host = "test1.com", ["content-type"] = "application/json"})
      local raw = cjson.decode(response)
      local body = cjson.decode(raw.postData.text)
      assert.are.equal(200, status)
      assert.are.equal("newvalue", body["newjsonparam"])
    end)
    it("should add new paramters on json POST when existing params exist", function()
      local response, status = http_client.post(STUB_POST_URL, {hello = "world"}, {host = "test1.com", ["content-type"] = "application/json"})
      local raw = cjson.decode(response)
      local body = cjson.decode(raw.postData.text)
      assert.are.equal(200, status)
      assert.are.equal("world", body["hello"])
      assert.are.equal("newvalue", body["newjsonparam"])
    end)
    it("should add new parameters on GET", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "test1.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.are.equal("value", body.queryString["newparam"])
    end)
    it("should change the host header", function()
      local response, status = http_client.get(spec_helper.PROXY_URL.."/get", {}, {host = "test2.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.are.equal("mark", body.headers["Host"])
    end)
  end)

  describe("Test removing parameters", function()
    it("should remove a header", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "test1.com", ["x-to-remove"] = "true"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.falsy(body.headers["x-to-remove"])
    end)
    it("should remove parameters on POST", function()
      local response, status = http_client.post(STUB_POST_URL, {["toremoveform"] = "yes", ["nottoremove"] = "yes"}, {host = "test1.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.falsy(body.postData.params["toremoveform"])
      assert.are.same("yes", body.postData.params["nottoremove"])
    end)
    it("should remove parameters on multipart POST", function()
      local response, status = http_client.post_multipart(STUB_POST_URL, {["toremoveform"] = "yes", ["nottoremove"] = "yes"}, {host = "test1.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.falsy(body.postData.params["toremoveform"])
      assert.are.same("yes", body.postData.params["nottoremove"])
    end)
    it("should remove parameters on json POST", function()
      local response, status = http_client.post(STUB_POST_URL, {["toremovejson"] = "yes", ["nottoremove"] = "yes"}, {host = "test1.com", ["content-type"] = "application/json"})
      local raw = cjson.decode(response)
      local body = cjson.decode(raw.postData.text)
      assert.are.equal(200, status)
      assert.falsy(body["toremovejson"])
      assert.are.same("yes", body["nottoremove"])
    end)
    it("should remove parameters on GET", function()
      local response, status = http_client.get(STUB_GET_URL, {["toremovequery"] = "yes", ["nottoremove"] = "yes"}, {host = "test1.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.falsy(body.queryString["toremovequery"])
      assert.are.equal("yes", body.queryString["nottoremove"])
    end)
  end)
end)
