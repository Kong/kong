local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"
local jwt = require "luajwt"

local STUB_GET_URL = spec_helper.STUB_GET_URL
local STUB_POST_URL = spec_helper.STUB_POST_URL

describe("Authentication Plugin", function()

  describe("JWT Authentication when secret is text", function()

    setup(function()
      spec_helper.prepare_db()
      spec_helper.insert_fixtures {
        api = {
          { name = "tests jwtauth", public_dns = "jwtauth.com", target_url = "http://mockbin.com" },
          { name = "tests jwtauth 2", public_dns = "jwtauth2.com", target_url = "http://mockbin.com" }
        },
        consumer = {
          { username = "jwtauth_tests_consumer" }
        },
        plugin_configuration = {
          { name = "jwtauth", value = { }, __api = 1 },
          { name = "jwtauth", value = { id_names = { "username" }, hide_credentials = true }, __api = 2 }
        },
        jwtauth_credential = {
          { secret = "example_key", __consumer = 1 }
        }
      }

      spec_helper.start_kong()
    end)

    teardown(function()
      spec_helper.stop_kong()
    end)


    it("should return invalid credentials when the credential value is wrong", function()
      local response, status = http_client.get(STUB_GET_URL, {id = "jwtauth_tests_consumer"}, {host = "jwtauth.com", authorization = "asd"})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Invalid authentication credentials", body.message)
    end)

    it("should return invalid credentials when only passing authorization", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "jwtauth.com", authorization = "asd"})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Invalid authentication credentials", body.message)
    end)

    it("should return invalid credentials when only passing id", function()
      local response, status = http_client.get(STUB_GET_URL, {id = "jwtauth_tests_consumer"}, {host = "jwtauth.com"})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Invalid authentication credentials", body.message)
    end)

    it("should return invalid credentials when the credential parameter name is wrong in GET", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "jwtauth.com", authorization123 = "Bearer dXNlcm5hbWU6cGFzc3dvcmQ="})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Invalid authentication credentials", body.message)
    end)

    it("should return invalid credentials when the credential parameter name is wrong in POST", function()
      local response, status = http_client.post(STUB_POST_URL, {}, {host = "jwtauth.com", authorization123 = "Bearer dXNlcm5hbWU6cGFzc3dvcmQ="})
      local body = cjson.decode(response)
      assert.are.equal(403, status)
      assert.are.equal("Invalid authentication credentials", body.message)
    end)

    it("should pass with GET", function()
      local key = "example_key"

      local payload = {
          iss = "12345678",
          nbf = os.time(),
          exp = os.time() + 3600,
      }

      local alg = "HS256"
      local token = jwt.encode(payload, key, alg)
      local response, status = http_client.get(STUB_GET_URL, {id = "jwtauth_tests_consumer"}, {host = "jwtauth.com", authorization = "Bearer " .. token})
      assert.are.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.are.equal("Bearer " .. token, parsed_response.headers.authorization)
    end)

    it("should pass with GET with id in headers", function()
      local key = "example_key"

      local payload = {
          iss = "12345678",
          nbf = os.time(),
          exp = os.time() + 3600,
      }

      local alg = "HS256"
      local token = jwt.encode(payload, key, alg)
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "jwtauth.com", authorization = "Bearer " .. token, id = "jwtauth_tests_consumer"})
      assert.are.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.are.equal("Bearer " .. token, parsed_response.headers.authorization)
      assert.are.equal("jwtauth_tests_consumer", parsed_response.headers.id)
    end)

    it("should pass with POST", function()
      local key = "example_key"

      local payload = {
          iss = "12345678",
          nbf = os.time(),
          exp = os.time() + 3600,
      }

      local alg = "HS256"
      local token = jwt.encode(payload, key, alg)
      local response, status = http_client.post(STUB_POST_URL, {id = "jwtauth_tests_consumer"}, {host = "jwtauth.com", authorization = "Bearer " .. token})
      assert.are.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.are.equal("Bearer " .. token, parsed_response.headers.authorization)
    end)

    it("should hide credentials with hide_credentials set", function()
      local key = "example_key"

      local payload = {
          iss = "12345678",
          nbf = os.time(),
          exp = os.time() + 3600,
      }

      local alg = "HS256"
      local token = jwt.encode(payload, key, alg)
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "jwtauth2.com", authorization = "Bearer " .. token, username = "jwtauth_tests_consumer"})
      assert.are.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.are.equal(nil, parsed_response.headers.authorization)
      assert.are.equal(nil, parsed_response.headers.id)
    end)
  end)

  describe("JWT Authentication when secret is base64 encoded", function()
    
    setup(function()
      spec_helper.prepare_db()
      spec_helper.insert_fixtures {
        api = {
          { name = "tests jwtauth", public_dns = "jwtauth.com", target_url = "http://mockbin.com" },
          { name = "tests jwtauth 2", public_dns = "jwtauth2.com", target_url = "http://mockbin.com" }
        },
        consumer = {
          { username = "jwtauth_tests_consumer" }
        },
        plugin_configuration = {
          { name = "jwtauth", value = { }, __api = 1 },
          { name = "jwtauth", value = { id_names = { "username" }, hide_credentials = true }, __api = 2 }
        },
        jwtauth_credential = {
          { secret = "ZXhhbXBsZV9rZXk=", __consumer = 1, secret_is_base64_encoded = true }
        }
      }

      spec_helper.start_kong()
    end)

    teardown(function()
      spec_helper.stop_kong()
    end)

    it("should return 200 success", function() 
      local key = "example_key"

      local payload = {
          iss = "12345678",
          nbf = os.time(),
          exp = os.time() + 3600,
      }

      local alg = "HS256"
      local token = jwt.encode(payload, key, alg)
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "jwtauth2.com", authorization = "Bearer " .. token, username = "jwtauth_tests_consumer"})
      assert.are.equal(200, status)
    end)

    it("should return 403 when signed with different key", function() 
      local key = "bad_key"

      local payload = {
          iss = "12345678",
          nbf = os.time(),
          exp = os.time() + 3600,
      }

      local alg = "HS256"
      local token = jwt.encode(payload, key, alg)
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "jwtauth2.com", authorization = "Bearer " .. token, username = "jwtauth_tests_consumer"})
      assert.are.equal(403, status)
    end)

  end)

  describe("JWT Authentication when secret is not base64 encoded but secret_is_base64_encoded is true ", function()
    
    setup(function()
      spec_helper.prepare_db()
      spec_helper.insert_fixtures {
        api = {
          { name = "tests jwtauth", public_dns = "jwtauth.com", target_url = "http://mockbin.com" },
          { name = "tests jwtauth 2", public_dns = "jwtauth2.com", target_url = "http://mockbin.com" }
        },
        consumer = {
          { username = "jwtauth_tests_consumer" }
        },
        plugin_configuration = {
          { name = "jwtauth", value = { }, __api = 1 },
          { name = "jwtauth", value = { id_names = { "username" }, hide_credentials = true }, __api = 2 }
        },
        jwtauth_credential = {
          { secret = "example_key", __consumer = 1, secret_is_base64_encoded = true }
        }
      }

      spec_helper.start_kong()
    end)

    teardown(function()
      spec_helper.stop_kong()
    end)

    it("should return 403 unauthorized", function() 
      local key = "example_key"

      local payload = {
          iss = "12345678",
          nbf = os.time(),
          exp = os.time() + 3600,
      }

      local alg = "HS256"
      local token = jwt.encode(payload, key, alg)
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "jwtauth2.com", authorization = "Bearer " .. token, username = "jwtauth_tests_consumer"})
      assert.are.equal(403, status)
    end)

  end)
end)
