local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local constants = require "kong.constants"
local access = require "kong.plugins.gelato.access"
local cjson = require "cjson"

local PROXY_URL = spec_helper.PROXY_URL

describe("Gelato Plugin", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        {request_host = "gelato.com", upstream_url = "http://mockbin.org"},
        {request_host = "gelato2.com", upstream_url = "http://mockbin.org"},
        {request_host = "gelato3.com", upstream_url = "http://mockbin.org"},
        {request_host = "gelato4.com", upstream_url = "http://mockbin.org"},
        {request_host = "gelato5.com", upstream_url = "http://mockbin.org"},
        {request_host = "gelato6.com", upstream_url = "http://mockbin.org"},
        {request_host = "gelato7.com", upstream_url = "http://mockbin.org"}
      },
      consumer = {
        {custom_id = "hello123"}
      },
      plugin = {
        {name = "gelato", config = { secret = "secret123"}, __api = 1},
        {name = "gelato", config = { secret = "secret123"}, __api = 2},
        {name = "gelato", config = { secret = "secret123"}, __api = 3},
        {name = "gelato", config = { secret = "secret123"}, __api = 4},
        {name = "gelato", config = { secret = "secret123"}, __api = 5},
        {name = "gelato", config = { secret = "secret123"}, __api = 6},
        {name = "gelato", config = { secret = "secret123"}, __api = 7},
        {name = "basic-auth", config = { hide_credentials = false }, __api = 2},
        {name = "key-auth", config = { hide_credentials = false }, __api = 3},
        {name = "oauth2", config = { scopes = { "email", "profile" } }, __api = 4 },
        {name = "basic-auth", config = { hide_credentials = false }, __api = 5},
        {name = "rate-limiting", config = { minute = 6 }, __api = 5 },
        {name = "rate-limiting", config = { minute = 3, second = 1}, __api = 5, __consumer = 1 },
        {name = "basic-auth", config = { hide_credentials = false }, __api = 6},
        {name = "request-size-limiting", config = {allowed_payload_size = 10}, __api = 6 },
        {name = "basic-auth", config = { hide_credentials = false }, __api = 7},
        { name = "response-ratelimiting", config = { limits = { video = { minute = 6, hour = 10 }, image = { minute = 4 } } }, __api = 7 }
      },
      basicauth_credential = {
        --{username = "username", password = "password", __consumer = 1}
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  local function get_api_id(host)
    local response, status = http_client.get(API_URL.."/apis/", { request_host = host })
    assert.equal(200, status)
    return cjson.decode(response).data[1].id
  end

  describe("Gelato", function()
    
    it("should return forbidden when secret is not valid", function()
      local response, status = http_client.get(PROXY_URL.."/_gelato", {}, {host = "gelato.com"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal("Invalid \"secret\"", body.message)
    end)

    it("should return error when secret is valid and API has no authentication", function()
      local response, status = http_client.get(PROXY_URL.."/_gelato", {}, {host = "gelato.com", authorization = "c2VjcmV0MTIzOg=="})
      local body = cjson.decode(response)
      assert.equal(400, status)
      assert.equal("The API either has not authentication, or has an unsupported authentication", body.message)
    end)

    it("should return success when secret is valid and API has authentication", function()
      local response, status = http_client.get(PROXY_URL.."/_gelato", {}, {host = "gelato2.com", authorization = "c2VjcmV0MTIzOg=="})
      local body = cjson.decode(response)
      assert.equal(400, status)
      assert.equal("Missing \"custom_id\"", body.message)
    end)

    it("should not provision a credential when the custom_id is missing", function()
      local response, status = http_client.post(PROXY_URL.."/_gelato", {}, {host = "gelato2.com", authorization = "c2VjcmV0MTIzOg=="})
      local body = cjson.decode(response)
      assert.equal(400, status)
      assert.equal("Missing \"custom_id\"", body.message)
    end)

    it("should not provision a credential when the custom_id is missing", function()
      local response, status = http_client.post(PROXY_URL.."/_gelato", {custom_id="  "}, {host = "gelato2.com", authorization = "c2VjcmV0MTIzOg=="})
      local body = cjson.decode(response)
      assert.equal(400, status)
      assert.equal("Missing \"custom_id\"", body.message)
    end)

    it("should provision a credential when the consumer does not exist", function()
      local response, status = http_client.post(PROXY_URL.."/_gelato", {custom_id="user123"}, {host = "gelato2.com", authorization = "c2VjcmV0MTIzOg=="})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("basic-auth", body.authentication_name)
      assert.truthy(body.credential.id)
      assert.truthy(body.credential.keys.username)
      assert.truthy(body.credential.keys.password)
    end)

    it("should return credentials if they have been created", function()
      local response, status = http_client.get(PROXY_URL.."/_gelato", {custom_id="user123"}, {host = "gelato2.com", authorization = "c2VjcmV0MTIzOg=="})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("basic-auth", body.authentication_name)
      assert.truthy(body.credentials)
      assert.equal(1, #body.credentials)
      assert.truthy(body.credentials[1].id)
      assert.truthy(body.credentials[1].keys.username)
      assert.truthy(body.credentials[1].keys.password)
    end)

    it("should provision a credential when the consumer exist", function()
      local response, status = http_client.post(PROXY_URL.."/_gelato", {custom_id="user123"}, {host = "gelato2.com", authorization = "c2VjcmV0MTIzOg=="})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("basic-auth", body.authentication_name)
      assert.truthy(body.credential.id)
      assert.truthy(body.credential.keys.username)
      assert.truthy(body.credential.keys.password)
    end)

    it("should return more than one credential if they have been created", function()
      local response, status = http_client.get(PROXY_URL.."/_gelato", {custom_id="user123"}, {host = "gelato2.com", authorization = "c2VjcmV0MTIzOg=="})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("basic-auth", body.authentication_name)
      assert.truthy(body.credentials)
      assert.equal(2, #body.credentials)
      assert.truthy(body.credentials[1].id)
      assert.truthy(body.credentials[1].keys.username)
      assert.truthy(body.credentials[1].keys.password)
      assert.truthy(body.credentials[2].id)
      assert.truthy(body.credentials[2].keys.username)
      assert.truthy(body.credentials[2].keys.password)
    end)

    it("should return error when deleting an unexisting credential", function()
      local response, status = http_client.delete(PROXY_URL.."/_gelato", {custom_id="user123"}, {host = "gelato2.com", authorization = "c2VjcmV0MTIzOg=="})
      local body = cjson.decode(response)
      assert.equal(404, status)
      assert.equal("Credential not found", body.message)
    end)

    it("should return error when deleting an unexisting consumer", function()
      local response, status = http_client.delete(PROXY_URL.."/_gelato", {custom_id="user124"}, {host = "gelato2.com", authorization = "c2VjcmV0MTIzOg=="})
      local body = cjson.decode(response)
      assert.equal(404, status)
      assert.equal("Consumer not found", body.message)
    end)

    it("should return error when deleting an unexisting credential", function()
      local response, status = http_client.delete(PROXY_URL.."/_gelato", {custom_id="user123", credential_id="asd"}, {host = "gelato2.com", authorization = "c2VjcmV0MTIzOg=="})
      local body = cjson.decode(response)
      assert.equal(404, status)
      assert.equal("Credential not found", body.message)
    end)

    it("should delete a credential", function()
      -- Retrieve credential ID
      local response, status = http_client.get(PROXY_URL.."/_gelato", {custom_id="user123"}, {host = "gelato2.com", authorization = "c2VjcmV0MTIzOg=="})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("basic-auth", body.authentication_name)
      assert.truthy(body.credentials)
      assert.equal(2, #body.credentials)
      assert.truthy(body.credentials[1].id)

      local response, status = http_client.delete(PROXY_URL.."/_gelato", {custom_id="user123", credential_id=body.credentials[1].id}, {host = "gelato2.com", authorization = "c2VjcmV0MTIzOg=="})
      assert.equal(200, status)

      local response, status = http_client.get(PROXY_URL.."/_gelato", {custom_id="user123"}, {host = "gelato2.com", authorization = "c2VjcmV0MTIzOg=="})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("basic-auth", body.authentication_name)
      assert.truthy(body.credentials)
      assert.equal(1, #body.credentials)
    end)

    it("should provision a key-auth", function()
      local response, status = http_client.post(PROXY_URL.."/_gelato", {custom_id="user123"}, {host = "gelato3.com", authorization = "c2VjcmV0MTIzOg=="})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("key-auth", body.authentication_name)
      assert.truthy(body.credential.id)
      assert.truthy(body.credential.keys["apikey"])
    end)

    it("should not provision an oauth2 without required parameters", function()
      local response, status = http_client.post(PROXY_URL.."/_gelato", {custom_id="user123"}, {host = "gelato4.com", authorization = "c2VjcmV0MTIzOg=="})
      local body = cjson.decode(response)
      assert.equal(400, status)
      assert.equal("redirect_uri=redirect_uri is required name=name is required", body.message)
    end)

     it("should provision an oauth2", function()
      local response, status = http_client.post(PROXY_URL.."/_gelato", {custom_id="user123", name="app", redirect_uri="http://google.com"}, {host = "gelato4.com", authorization = "c2VjcmV0MTIzOg=="})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("oauth2", body.authentication_name)
      assert.truthy(body.credential.id)
      assert.truthy(body.credential.keys.client_id)
      assert.truthy(body.credential.keys.client_secret)
      assert.truthy(body.credential.keys.name)
      assert.truthy(body.credential.keys.redirect_uri)
    end)
    
    it("should provision a credential and return the rate limiting notes", function()
      local response, status = http_client.post(PROXY_URL.."/_gelato", {custom_id="user123"}, {host = "gelato5.com", authorization = "c2VjcmV0MTIzOg=="})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("basic-auth", body.authentication_name)
      assert.truthy(body.credential.id)
      assert.truthy(body.credential.keys.username)
      assert.truthy(body.credential.keys.password)

      assert.equal(1, #body.notes)
      assert.equal("Rate Limiting", body.notes[1].description)
      assert.equal("6 requests per minute", body.notes[1].extended)
    end)

    it("should provision a credential and return the request size limit notes for the specific consumer", function()
      local response, status = http_client.post(PROXY_URL.."/_gelato", {custom_id="hello123"}, {host = "gelato6.com", authorization = "c2VjcmV0MTIzOg=="})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("basic-auth", body.authentication_name)
      assert.truthy(body.credential.id)
      assert.truthy(body.credential.keys.username)
      assert.truthy(body.credential.keys.password)

      assert.equal(1, #body.notes)
      assert.equal("Request Size Limiting", body.notes[1].description)
      assert.equal("Maximum allowed request size is 10MB", body.notes[1].extended)
    end)

    it("should provision a credential and return the response rate limiting notes for the specific consumer", function()
      local response, status = http_client.post(PROXY_URL.."/_gelato", {custom_id="hello123"}, {host = "gelato7.com", authorization = "c2VjcmV0MTIzOg=="})
      local body = cjson.decode(response)
      assert.equal(200, status)
      assert.equal("basic-auth", body.authentication_name)
      assert.truthy(body.credential.id)
      assert.truthy(body.credential.keys.username)
      assert.truthy(body.credential.keys.password)

      assert.equal(1, #body.notes)
      assert.equal("Response Rate Limiting", body.notes[1].description)
      assert.equal("6 requests per minute for video, 10 requests per hour for video, 4 requests per minute for image", body.notes[1].extended)
    end)
    
  end)

end)
