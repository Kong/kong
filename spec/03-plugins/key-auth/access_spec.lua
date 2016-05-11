local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"
local meta = require "kong.meta"

local STUB_GET_URL = spec_helper.STUB_GET_URL
local STUB_POST_URL = spec_helper.STUB_POST_URL

describe("key-auth plugin", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        {name = "tests-auth1", request_host = "keyauth1.com", upstream_url = "http://mockbin.com"},
        {name = "tests-auth2", request_host = "keyauth2.com", upstream_url = "http://mockbin.com"}
      },
      consumer = {
        {username = "auth_tests_consumer"}
      },
      plugin = {
        {name = "key-auth", config = {key_names = {"apikey"}}, __api = 1},
        {name = "key-auth", config = {key_names = {"apikey"}, hide_credentials = true}, __api = 2}
      },
      keyauth_credential = {
        {key = "apikey123", __consumer = 1}
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("Query Authentication", function()

     it("should return invalid credentials and www-authenticate header when the credential is missing", function()
      local response, status, headers = http_client.get(STUB_GET_URL, {}, {host = "keyauth1.com"})
      local body = cjson.decode(response)
      assert.equal(401, status)
      assert.equal('Key realm="'..meta._NAME..'"', headers["www-authenticate"])
      assert.equal("No API Key found in headers, body or querystring", body.message)
    end)

    it("should return invalid credentials when the credential value is wrong", function()
      local response, status = http_client.get(STUB_GET_URL, {apikey = "asd"}, {host = "keyauth1.com"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal("Invalid authentication credentials", body.message)
    end)

    it("should reply with 401 and www-authenticate header when the credential parameter is missing", function()
      local response, status, headers = http_client.get(STUB_GET_URL, {apikey123 = "apikey123"}, {host = "keyauth1.com"})
      local body = cjson.decode(response)
      assert.equal(401, status)
      assert.equal('Key realm="'..meta._NAME..'"', headers["www-authenticate"])
      assert.equal("No API Key found in headers, body or querystring", body.message)
    end)

    it("should reply 401 and www-authenticate header when the credential parameter name is wrong in GET", function()
      local response, status, headers = http_client.get(STUB_GET_URL, {apikey123 = "apikey123"}, {host = "keyauth1.com"})
      local body = cjson.decode(response)
      assert.equal(401, status)
      assert.equal('Key realm="'..meta._NAME..'"', headers["www-authenticate"])
      assert.equal("No API Key found in headers, body or querystring", body.message)
    end)

    it("should reply 401 and www-authenticate header when the credential parameter name is wrong in POST", function()
      local response, status, headers = http_client.post(STUB_POST_URL, {apikey123 = "apikey123"}, {host = "keyauth1.com"})
      local body = cjson.decode(response)
      assert.equal(401, status)
      assert.equal('Key realm="'..meta._NAME..'"', headers["www-authenticate"])
      assert.equal("No API Key found in headers, body or querystring", body.message)
    end)

    it("should pass with GET", function()
      local response, status = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host = "keyauth1.com"})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.equal("apikey123", parsed_response.queryString.apikey)
    end)

    it("should reply 401 and www-authenticate header when the credential parameter name is wrong in GET header", function()
      local response, status, headers = http_client.get(STUB_GET_URL, {}, {host = "keyauth1.com", apikey123 = "apikey123"})
      local body = cjson.decode(response)
      assert.equal(401, status)
      assert.equal('Key realm="'..meta._NAME..'"', headers["www-authenticate"])
      assert.equal("No API Key found in headers, body or querystring", body.message)
    end)

    it("should reply 401 and www-authenticate header when the credential parameter name is wrong in POST header", function()
      local response, status, headers = http_client.post(STUB_POST_URL, {}, {host = "keyauth1.com", apikey123 = "apikey123"})
      local body = cjson.decode(response)
      assert.equal(401, status)
      assert.equal('Key realm="'..meta._NAME..'"', headers["www-authenticate"])
      assert.equal("No API Key found in headers, body or querystring", body.message)
    end)

    it("should set right headers", function()
      local response, status = http_client.post(STUB_POST_URL, {}, {apikey = "apikey123", host = "keyauth1.com"})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.truthy(parsed_response.headers["x-consumer-id"])
      assert.truthy(parsed_response.headers["x-consumer-username"])
      assert.equal("auth_tests_consumer", parsed_response.headers["x-consumer-username"])
    end)

    describe("Hide credentials", function()

      it("should pass with POST multipart and hide credentials", function()
        local MB = 1024 * 1024
        local file1_txt = string.rep(".", 5 * MB)
        local response, status = http_client.post_multipart(STUB_POST_URL, {file = file1_txt, wot = "wat"}, {apikey = "apikey123", host = "keyauth2.com"})
        assert.equal(200, status)
        local parsed_response = cjson.decode(response)
        assert.falsy(parsed_response.postData.params.apikey)
        assert.equal("wat", parsed_response.postData.params.wot)
      end)

      it("should pass with GET and hide credentials", function()
        local response, status = http_client.get(STUB_GET_URL, {}, {host = "keyauth2.com", apikey = "apikey123"})
        assert.equal(200, status)
        local parsed_response = cjson.decode(response)
        assert.falsy(parsed_response.headers.apikey)
      end)

      it("should pass with GET and hide credentials and another param", function()
        local response, status = http_client.get(STUB_GET_URL, {}, {host = "keyauth2.com", apikey = "apikey123", foo = "bar"})
        assert.equal(200, status)
        local parsed_response = cjson.decode(response)
        assert.falsy(parsed_response.headers.apikey)
        assert.equal("bar", parsed_response.headers.foo)
      end)

      it("should not pass with GET and hide credentials", function()
        local response, status = http_client.get(STUB_GET_URL, {}, {host = "keyauth2.com", apikey = "apikey123123"})
        local body = cjson.decode(response)
        assert.equal(403, status)
        assert.equal("Invalid authentication credentials", body.message)
      end)

      it("should pass with GET and hide credentials and another param", function()
        local response, status = http_client.get(STUB_GET_URL, {}, {host = "keyauth2.com", apikey = "apikey123", wot = "wat"})
        assert.equal(200, status)
        local parsed_response = cjson.decode(response)
        assert.falsy(parsed_response.headers.apikey)
        assert.equal("wat", parsed_response.headers.wot)
      end)

      it("should not pass with GET and hide credentials", function()
        local response, status = http_client.get(STUB_GET_URL, {}, {host = "keyauth2.com", apikey = "apikey123123"})
        local body = cjson.decode(response)
        assert.equal(403, status)
        assert.equal("Invalid authentication credentials", body.message)
      end)

      it("should pass with GET and hide credentials in querystring", function()
        local response, status = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host = "keyauth2.com"})
        assert.equal(200, status)
        local parsed_response = cjson.decode(response)
        assert.falsy(parsed_response.queryString.apikey)
      end)

    end)
  end)
end)
