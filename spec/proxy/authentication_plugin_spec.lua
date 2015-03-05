local spec_helper = require "spec.spec_helpers"
local utils = require "kong.tools.utils"
local cjson = require "cjson"

local kProxyURL = spec_helper.PROXY_URL
local kPostURL = kProxyURL.."/post"
local kGetURL = kProxyURL.."/get"

describe("Authentication Plugin #proxy", function()

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
      local response, status, headers = utils.get(kGetURL, {apikey = "asd"}, {host = "test.com"})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Your authentication credentials are invalid", body.message)
    end)

    it("should return invalid credentials when the credential parameter name is wrong in GET", function()
      local response, status, headers = utils.get(kGetURL, {apikey123 = "apikey123"}, {host = "test.com"})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Your authentication credentials are invalid", body.message)
    end)

    it("should return invalid credentials when the credential parameter name is wrong in POST", function()
      local response, status, headers = utils.post(kPostURL, {apikey123 = "apikey123"}, {host = "test.com"})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Your authentication credentials are invalid", body.message)
    end)

    it("should pass with GET", function()
      local response, status, headers = utils.get(kGetURL, {apikey = "apikey123"}, {host = "test.com"})
      assert.are.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.are.equal("apikey123", parsed_response.args.apikey)
    end)

    it("should pass with POST", function()
      local response, status, headers = utils.post(kPostURL, {apikey = "apikey123"}, {host = "test.com"})
      assert.are.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.are.equal("apikey123", parsed_response.form.apikey)
    end)

  end)

  describe("Header Authentication", function()

    it("should return invalid credentials when the credential value is wrong", function()
      local response, status, headers = utils.get(kGetURL, {}, {host = "test2.com", apikey = "asd"})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Your authentication credentials are invalid", body.message)
    end)

    it("should return invalid credentials when the credential parameter name is wrong in GET", function()
      local response, status, headers = utils.get(kGetURL, {}, {host = "test2.com", apikey123 = "apikey123"})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Your authentication credentials are invalid", body.message)
    end)

    it("should return invalid credentials when the credential parameter name is wrong in POST", function()
      local response, status, headers = utils.post(kPostURL, {}, {host = "test2.com", apikey123 = "apikey123"})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Your authentication credentials are invalid", body.message)
    end)

    it("should pass with GET", function()
      local response, status, headers = utils.get(kGetURL, {}, {host = "test2.com", apikey = "apikey123"})
      assert.are.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.are.equal("apikey123", parsed_response.headers.Apikey)
    end)

    it("should pass with POST", function()
      local response, status, headers = utils.post(kPostURL, {}, {host = "test2.com", apikey = "apikey123"})
      assert.are.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.are.equal("apikey123", parsed_response.headers.Apikey)
    end)

  end)

  describe("Basic Authentication", function()

    it("should return invalid credentials when the credential value is wrong", function()
      local response, status, headers = utils.get(kGetURL, {}, {host = "test3.com", authorization = "asd"})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Your authentication credentials are invalid", body.message)
    end)

    it("should not pass when passing only the password", function()
      local response, status, headers = utils.get(kGetURL, {}, {host = "test3.com", authorization = "Basic OmFwaWtleTEyMw=="})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Your authentication credentials are invalid", body.message)
    end)

    it("should not pass when passing only the username", function()
      local response, status, headers = utils.get(kGetURL, {}, {host = "test3.com", authorization = "Basic dXNlcjEyMzo="})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Your authentication credentials are invalid", body.message)
    end)

    it("should return invalid credentials when the credential parameter name is wrong in GET", function()
      local response, status, headers = utils.get(kGetURL, {}, {host = "test3.com", authorization123 = "Basic dXNlcm5hbWU6cGFzc3dvcmQ="})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Your authentication credentials are invalid", body.message)
    end)

    it("should return invalid credentials when the credential parameter name is wrong in POST", function()
      local response, status, headers = utils.post(kPostURL, {}, {host = "test3.com", authorization123 = "Basic dXNlcm5hbWU6cGFzc3dvcmQ="})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Your authentication credentials are invalid", body.message)
    end)

    it("should pass with GET", function()
      local response, status, headers = utils.get(kGetURL, {}, {host = "test3.com", authorization = "Basic dXNlcm5hbWU6cGFzc3dvcmQ="})
      assert.are.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.are.equal("Basic dXNlcm5hbWU6cGFzc3dvcmQ=", parsed_response.headers.Authorization)
    end)

    it("should pass with POST", function()
      local response, status, headers = utils.post(kPostURL, {}, {host = "test3.com", authorization = "Basic dXNlcm5hbWU6cGFzc3dvcmQ="})
      assert.are.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.are.equal("Basic dXNlcm5hbWU6cGFzc3dvcmQ=", parsed_response.headers.Authorization)
    end)

  end)
end)
