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
        {name = "tests-request-transformer-2", request_host = "test2.com", upstream_url = "http://httpbin.org"},
        {name = "tests-request-transformer-3", request_host = "test3.com", upstream_url = "http://mockbin.com"},
        {name = "tests-request-transformer-4", request_host = "test4.com", upstream_url = "http://mockbin.com"},
        {name = "tests-request-transformer-5", request_host = "test5.com", upstream_url = "http://mockbin.com"},
        {name = "tests-request-transformer-6", request_host = "test6.com", upstream_url = "http://mockbin.com"},
      },
      plugin = {
        {
          name = "request-transformer",
          config = {
            add = {
              headers = {"h1:v1", "h2:v2"},
              querystring = {"q1:v1"},
              body = {"p1:v1"}
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
        },
        {
          name = "request-transformer",
          config = {
            add = {
              headers = {"x-added:a1", "x-added2:b1", "x-added3:c2"},
              querystring = {"query-added:newvalue", "p1:a1"},
              body = {"newformparam:newvalue"}
            },
            remove = {
              headers = {"x-to-remove"},
              querystring = {"toremovequery"}
            },
            append = {
              headers = {"x-added:a2", "x-added:a3"},
              querystring = {"p1:a2", "p2:b1"}
            },
            replace = {
              headers = {"x-to-replace:false"},
              querystring = {"toreplacequery:no"}
            }
          },
          __api = 3
        },
        {
          name = "request-transformer",
          config = {
            remove = {
              headers = {"x-to-remove"},
              querystring = {"q1"},
              body = {"toremoveform"}
            }
          },
          __api = 4
        },
        {
          name = "request-transformer",
          config = {
            replace = {
              headers = {"h1:v1"},
              querystring = {"q1:v1"},
              body = {"p1:v1"}
            }
          },
          __api = 5
        },
        {
          name = "request-transformer",
          config = {
            append = {
              headers = {"h1:v1", "h1:v2", "h2:v1",},
              querystring = {"q1:v1", "q1:v2", "q2:v1"},
              body = {"p1:v1", "p1:v2", "p2:v1"}
            }
          },
          __api = 6
        }
      },
    }
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("Test remove", function()
    it("should remove specified header", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "test4.com", ["x-to-remove"] = "true", ["x-another-header"] = "true"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.falsy(body.headers["x-to-remove"])
      assert.equal("true", body.headers["x-another-header"])
    end)
    it("should remove parameters on url encoded form POST", function()
      local response, status = http_client.post(STUB_POST_URL, {["toremoveform"] = "yes", ["nottoremove"] = "yes"}, {host = "test4.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.falsy(body.postData.params["toremoveform"])
      assert.equal("yes", body.postData.params["nottoremove"])
    end)
    it("should remove parameters from JSON body in POST", function()
      local response, status = http_client.post(STUB_POST_URL, {["toremoveform"] = "yes", ["nottoremove"] = "yes"}, {host = "test4.com", ["content-type"] = "application/json"})
      local body = cjson.decode(cjson.decode(response).postData.text)
      assert.equal(200, status)
      assert.falsy(body["toremoveform"])
      assert.equal("yes", body["nottoremove"])
    end)
    it("should not fail if JSON body is malformed in POST", function()
      local response, status = http_client.post(STUB_POST_URL, "malformed json body", {host = "test4.com", ["content-type"] = "application/json"})
      local body = cjson.decode(response).postData.text
      assert.equal(200, status)
      assert.equal("malformed json body", body)
    end)
    it("should not fail if body is empty and content type is application/json in POST", function()
      local response, status = http_client.post(STUB_POST_URL, nil, {host = "test4.com", ["content-type"] = "application/json"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal('{}', body.postData.text)
      assert.equal("2", body.headers["content-length"])
    end)
    it("should not fail if body is empty in POST", function()
      local response, status = http_client.post(STUB_POST_URL, nil, {host = "test4.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.same({}, body.postData.params)
      assert.equal('', body.postData.text)
      assert.equal("0", body.headers["content-length"])
    end)
    it("should remove parameters on multipart POST", function()
      local response, status = http_client.post_multipart(STUB_POST_URL, {["toremoveform"] = "yes", ["nottoremove"] = "yes"}, {host = "test4.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.falsy(body.postData.params["toremoveform"])
      assert.equal("yes", body.postData.params["nottoremove"])
    end)
    it("should remove queryString on GET if it exist", function()
        local response, status = http_client.post(STUB_POST_URL.."/?q1=v1&q2=v2", {hello = "world"}, {host = "test4.com"})
        local body = cjson.decode(response)
        assert.equal(200, status)
        assert.falsy(body.queryString["q1"])
        assert.equal("v2", body.queryString["q2"])
    end)
  end)

  describe("Test replace", function()
    it("should replace specified header if it exist", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "test5.com", ["h1"] = "V", ["h2"] = "v2"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("v1", body.headers["h1"])
      assert.equal("v2", body.headers["h2"])
    end)
    it("should not add as new header if header does not exist", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "test5.com", ["h2"] = "v2"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.falsy(body.headers["h1"])
      assert.equal("v2", body.headers["h2"])
    end)
    it("should replace specified parameters in url encoded body on POST", function()
      local response, status = http_client.post(STUB_POST_URL, {["p1"] = "v", ["p2"] = "v1"}, {host = "test5.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("v1", body.postData.params["p1"])
      assert.equal("v1", body.postData.params["p2"])
    end)
    it("should not add as new parameter in url encoded body if parameter does not exist on POST", function()
      local response, status = http_client.post(STUB_POST_URL, {["p2"] = "v1"}, {host = "test5.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.falsy(body.postData.params["p1"])
      assert.equal("v1", body.postData.params["p2"])
    end)
    it("should replace specified parameters in json body on POST", function()
      local response, status = http_client.post(STUB_POST_URL, {["p1"] = "v", ["p2"] = "v1"}, {host = "test5.com", ["content-type"] = "application/json"})
      local body = cjson.decode(cjson.decode(response).postData.text)
      assert.equal(200, status)
      assert.equal("v1", body["p1"])
      assert.equal("v1", body["p2"])
    end)
    it("should not fail if JSON body is malformed in POST", function()
      local response, status = http_client.post(STUB_POST_URL, "malformed json body", {host = "test5.com", ["content-type"] = "application/json"})
      local body = cjson.decode(response).postData.text
      assert.equal(200, status)
      assert.equal("malformed json body", body)
    end)
    it("should not add as new parameter in json if parameter does not exist on POST", function()
      local response, status = http_client.post(STUB_POST_URL, {["p2"] = "v1"}, {host = "test5.com", ["content-type"] = "application/json"})
      local body = cjson.decode(cjson.decode(response).postData.text)
      assert.equal(200, status)
      assert.falsy(body["p1"])
      assert.equal("v1", body["p2"])
    end)
    it("should replace specified parameters on multipart POST", function()
      local response, status = http_client.post_multipart(STUB_POST_URL, {["p1"] = "v", ["p2"] = "v1"}, {host = "test5.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("v1", body.postData.params["p1"])
      assert.equal("v1", body.postData.params["p2"])
    end)
    it("should not add as new parameter if parameter does not exist on multipart POST", function()
      local response, status = http_client.post_multipart(STUB_POST_URL, {["p2"] = "v1"}, {host = "test5.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.falsy(body.postData.params["p1"])
      assert.equal("v1", body.postData.params["p2"])
    end)
    it("should replace queryString on POST if it exist", function()
        local response, status = http_client.post(STUB_POST_URL.."/?q1=v&q2=v2", {hello = "world"}, {host = "test5.com"})
        local body = cjson.decode(response)
        assert.equal(200, status)
        assert.equal("v1", body.queryString["q1"])
        assert.equal("v2", body.queryString["q2"])
    end)
    it("should not add new queryString on POST if it does not exist", function()
        local response, status = http_client.post(STUB_POST_URL.."/?q2=v2", {hello = "world"}, {host = "test5.com"})
        local body = cjson.decode(response)
        assert.equal(200, status)
        assert.falsy(body.queryString["q1"])
        assert.equal("v2", body.queryString["q2"])
    end)
  end)

  describe("Test add", function()
    it("should add new headers", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "test1.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("v1", body.headers["h1"])
      assert.equal("v2", body.headers["h2"])
    end)
    it("should not change or append value if header already exists", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "test1.com", h1 = "v3"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("v3", body.headers["h1"])
      assert.equal("v2", body.headers["h2"])
    end)
    it("should add new parameter in url encoded body on POST", function()
      local response, status = http_client.post(STUB_POST_URL, {hello = "world"}, {host = "test1.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("world", body.postData.params["hello"])
      assert.equal("v1", body.postData.params["p1"])
    end)
    it("should not change or append value to parameter in url encoded body on POST when parameter exists", function()
      local response, status = http_client.post(STUB_POST_URL, {hello = "world"}, {host = "test1.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("world", body.postData.params["hello"])
      assert.equal("v1", body.postData.params["p1"])
    end)
    it("should add new parameter in JSON body on POST", function()
      local response, status = http_client.post(STUB_POST_URL, {hello = "world"}, {host = "test1.com", ["content-type"] = "application/json"})
      local body = cjson.decode(cjson.decode(response).postData.text)
      assert.equal(200, status)
      assert.equal("world", body["hello"])
      assert.equal("v1", body["p1"])
    end)
    it("should not change or append value to parameter in JSON on POST when parameter exists", function()
      local response, status = http_client.post(STUB_POST_URL, {hello = "world"}, {host = "test1.com", ["content-type"] = "application/json"})
      local body = cjson.decode(cjson.decode(response).postData.text)
      assert.equal(200, status)
      assert.equal("world", body["hello"])
      assert.equal("v1", body["p1"])
    end)
    it("should not fail if JSON body is malformed in POST", function()
      local response, status = http_client.post(STUB_POST_URL, "malformed json body", {host = "test1.com", ["content-type"] = "application/json"})
      local body = cjson.decode(response).postData.text
      assert.equal(200, status)
      assert.equal("malformed json body", body)
    end)
    it("should add new parameter on multipart POST", function()
      local response, status = http_client.post_multipart(STUB_POST_URL, {}, {host = "test1.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("v1", body.postData.params["p1"])
    end)
    it("should not change or append value to parameter on multipart POST when parameter exists", function()
      local response, status = http_client.post_multipart(STUB_POST_URL, { hello = "world"}, {host = "test1.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("world", body.postData.params["hello"])
      assert.equal("v1", body.postData.params["p1"])
    end)
    it("should add new querystring on GET", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "test1.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("v1", body.queryString["q1"])
    end)
    it("should not change or append value to querystring on GET if querystring exists", function()
      local response, status = http_client.get(STUB_GET_URL, {q1 = "v2"}, {host = "test1.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("v2", body.queryString["q1"])
    end)
    it("should not change the host header", function()
      local response, status = http_client.get(spec_helper.PROXY_URL.."/get", {}, {host = "test2.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("httpbin.org", body.headers["Host"])
    end)
  end)

  describe("Test append ", function()
    it("should add a new header if header does not exists", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "test6.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("v1", body.headers["h2"])
    end)
    it("should append values to existing headers", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "test6.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("v1, v2", body.headers["h1"])
    end)
    it("should add new querystring if querystring does not exists", function()
      local response, status = http_client.post(STUB_POST_URL, {hello = "world"}, {host = "test6.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("v1", body.queryString["q2"])
    end)
    it("should append values to existing querystring", function()
      local response, status = http_client.post(STUB_POST_URL, {hello = "world"}, {host = "test6.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.same({"v1", "v2"}, body.queryString["q1"])
    end)
    it("should add new parameter in url encoded body on POST if it does not exist", function()
      local response, status = http_client.post(STUB_POST_URL, {}, {host = "test6.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.same({"v1", "v2"}, body.postData.params["p1"])
      assert.equal("v1", body.postData.params["p2"])
    end)
    it("should append values to existing parameter in url encoded body if parameter already exist on POST", function()
      local response, status = http_client.post(STUB_POST_URL, {p1 = "v0"}, {host = "test6.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.same({"v0", "v1", "v2"}, body.postData.params["p1"])
      assert.equal("v1", body.postData.params["p2"])
    end)
    it("should not fail if JSON body is malformed in POST", function()
      local response, status = http_client.post(STUB_POST_URL, "malformed json body", {host = "test6.com", ["content-type"] = "application/json"})
      local body = cjson.decode(response).postData.text
      assert.equal(200, status)
      assert.equal("malformed json body", body)
    end)
    it("should not change or append value to parameter on multipart POST", function()
      local response, status = http_client.post_multipart(STUB_POST_URL, {p1 = "v0"}, {host = "test6.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("v0", body.postData.params["p1"])
    end)
  end)

  describe("Test for remove, replace, add and append ", function()
    it("should remove a header", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "test3.com", ["x-to-remove"] = "true"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.falsy(body.headers["x-to-remove"])
    end)
    it("should replace value of header, if header exist", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "test3.com", ["x-to-replace"] = "true"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("false", body.headers["x-to-replace"])
    end)
    it("should not add new header if to be replaced header does not exist", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "test3.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.falsy(body.headers["x-to-replace"])
    end)
    it("should add new header if missing", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "test3.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("b1", body.headers["x-added2"])
    end)
    it("should not add new header if it already exist", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "test3.com", ["x-added3"] = "c1"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("c1", body.headers["x-added3"])
    end)
    it("should append values to existing headers", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "test3.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("a1, a2, a3", body.headers["x-added"])
    end)
    it("should add new parameters on POST when query string key missing", function()
      local response, status = http_client.post(STUB_POST_URL, {hello = "world"}, {host = "test3.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("b1", body.queryString["p2"])
    end)
    it("should remove parameters on GET", function()
      local response, status = http_client.get(STUB_GET_URL, {["toremovequery"] = "yes", ["nottoremove"] = "yes"}, {host = "test3.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.falsy(body.queryString["toremovequery"])
      assert.equal("yes", body.queryString["nottoremove"])
    end)
    it("should replace parameters on GET", function()
      local response, status = http_client.get(STUB_GET_URL, {["toreplacequery"] = "yes"}, {host = "test3.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("no", body.queryString["toreplacequery"])
    end)
    it("should not add new parameter if to be replaced parameters does not exist on GET", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "test3.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.falsy(body.queryString["toreplacequery"])
    end)
    it("should add parameters on GET if it does not exist", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "test3.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("newvalue", body.queryString["query-added"])
    end)
    it("should not add new parameter if to be added parameters already exist on GET", function()
      local response, status = http_client.get(STUB_GET_URL, {["query-added"] = "oldvalue"}, {host = "test3.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("oldvalue", body.queryString["query-added"])
    end)
    it("should append parameters on GET", function()
      local response, status = http_client.post(STUB_POST_URL.."/?q1=20", {hello = "world"}, {host = "test3.com"})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("a1", body.queryString["p1"][1])
      assert.equal("a2", body.queryString["p1"][2])
      assert.equal("20", body.queryString["q1"])
    end)
  end)
end)
