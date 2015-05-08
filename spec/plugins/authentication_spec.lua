local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"

STUB_GET_URL = spec_helper.STUB_GET_URL
STUB_POST_URL = spec_helper.STUB_POST_URL

describe("Authentication Plugin", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
    spec_helper.reset_db()
  end)

  describe("Query Authentication", function()

    it("should return invalid credentials when the credential value is wrong", function()
      local response, status, headers = http_client.get(STUB_GET_URL, {apikey = "asd"}, {host = "test1.com"})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Invalid authentication credentials", body.message)
    end)

    it("should return invalid credentials when the credential parameter name is wrong in GET", function()
      local response, status, headers = http_client.get(STUB_GET_URL, {apikey123 = "apikey123"}, {host = "test1.com"})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Invalid authentication credentials", body.message)
    end)

    it("should return invalid credentials when the credential parameter name is wrong in POST", function()
      local response, status, headers = http_client.post(STUB_POST_URL, {apikey123 = "apikey123"}, {host = "test1.com"})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Invalid authentication credentials", body.message)
    end)

    it("should pass with GET", function()
      local response, status, headers = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host = "test1.com"})
      assert.are.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.are.equal("apikey123", parsed_response.queryString.apikey)
    end)

    it("should pass with POST", function()
      local response, status, headers = http_client.post(STUB_POST_URL, {apikey = "apikey123"}, {host = "test1.com"})
      assert.are.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.are.equal("apikey123", parsed_response.postData.params.apikey)
    end)

    it("should return invalid credentials when the credential parameter name is wrong in GET header", function()
      local response, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test1.com", apikey123 = "apikey123"})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Invalid authentication credentials", body.message)
    end)

    it("should return invalid credentials when the credential parameter name is wrong in POST header", function()
      local response, status, headers = http_client.post(STUB_POST_URL, {}, {host = "test1.com", apikey123 = "apikey123"})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Invalid authentication credentials", body.message)
    end)

    describe("Hide credentials", function()

      it("should pass with POST and hide credentials", function()
        local response, status, headers = http_client.post(STUB_POST_URL, {apikey = "apikey123", wot = "wat"}, {host = "test3.com"})
        assert.are.equal(200, status)
        local parsed_response = cjson.decode(response)
        assert.falsy(parsed_response.postData.params.apikey)
        assert.are.equal("wat", parsed_response.postData.params.wot)
      end)

      it("should pass with POST multipart and hide credentials", function()
        local response, status, headers = http_client.post_multipart(STUB_POST_URL, {apikey = "apikey123", wot = "wat"}, {host = "test3.com"})
        assert.are.equal(200, status)
        local parsed_response = cjson.decode(response)
        assert.falsy(parsed_response.postData.params.apikey)
        assert.are.equal("wat", parsed_response.postData.params.wot)
      end)

      it("should pass with GET and hide credentials", function()
        local response, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test3.com", apikey = "apikey123"})
        assert.are.equal(200, status)
        local parsed_response = cjson.decode(response)
        assert.falsy(parsed_response.headers.apikey)
      end)

      it("should pass with GET and hide credentials and another param", function()
        local response, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test3.com", apikey = "apikey123", foo = "bar"})
        assert.are.equal(200, status)
        local parsed_response = cjson.decode(response)
        assert.falsy(parsed_response.headers.apikey)
        assert.are.equal("bar", parsed_response.headers.foo)
      end)

      it("should not pass with GET and hide credentials", function()
        local response, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test3.com", apikey = "apikey123123"})
        local body = cjson.decode(response)
        assert.are.equal(403, status)
        assert.are.equal("Invalid authentication credentials", body.message)
      end)

      it("should pass with GET and hide credentials and another param", function()
        local response, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test3.com", apikey = "apikey123", wot = "wat"})
        assert.are.equal(200, status)
        local parsed_response = cjson.decode(response)
        assert.falsy(parsed_response.headers.apikey)
        assert.are.equal("wat", parsed_response.headers.wot)
      end)

      it("should not pass with GET and hide credentials", function()
        local response, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test3.com", apikey = "apikey123123"})
        local body = cjson.decode(response)
        assert.are.equal(403, status)
        assert.are.equal("Invalid authentication credentials", body.message)
      end)
      
      it("should pass with GET and hide credentials in querystring", function()
        local response, status, headers = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host = "test3.com"})
        assert.are.equal(200, status)
        local parsed_response = cjson.decode(response)
        assert.falsy(parsed_response.queryString.apikey)
      end)

    end)

  end)

  describe("Basic Authentication", function()

    it("should return invalid credentials when the credential value is wrong", function()
      local response, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test2.com", authorization = "asd"})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Invalid authentication credentials", body.message)
    end)

    it("should not pass when passing only the password", function()
      local response, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test2.com", authorization = "Basic OmFwaWtleTEyMw=="})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Invalid authentication credentials", body.message)
    end)

    it("should not pass when passing only the username", function()
      local response, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test2.com", authorization = "Basic dXNlcjEyMzo="})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Invalid authentication credentials", body.message)
    end)

    it("should return invalid credentials when the credential parameter name is wrong in GET", function()
      local response, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test2.com", authorization123 = "Basic dXNlcm5hbWU6cGFzc3dvcmQ="})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Invalid authentication credentials", body.message)
    end)

    it("should return invalid credentials when the credential parameter name is wrong in POST", function()
      local response, status, headers = http_client.post(STUB_POST_URL, {}, {host = "test2.com", authorization123 = "Basic dXNlcm5hbWU6cGFzc3dvcmQ="})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Invalid authentication credentials", body.message)
    end)

    it("should pass with GET", function()
      local response, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test2.com", authorization = "Basic dXNlcm5hbWU6cGFzc3dvcmQ="})
      assert.are.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.are.equal("Basic dXNlcm5hbWU6cGFzc3dvcmQ=", parsed_response.headers.authorization)
    end)
    
    it("should pass with POST", function()
      local response, status, headers = http_client.post(STUB_POST_URL, {}, {host = "test2.com", authorization = "Basic dXNlcm5hbWU6cGFzc3dvcmQ="})
      assert.are.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.are.equal("Basic dXNlcm5hbWU6cGFzc3dvcmQ=", parsed_response.headers.authorization)
    end)

  end)

end)
