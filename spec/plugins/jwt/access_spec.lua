local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local json = require "cjson"
local jwt_encoder = require "kong.plugins.jwt.jwt_parser"
local base64 = require "base64"

local STUB_GET_URL = spec_helper.STUB_GET_URL

local PAYLOAD = {
  iss = nil,
  nbf = os.time(),
  iat = os.time(),
  exp = os.time() + 3600
}

describe("JWT access", function()
  local jwt_secret, base64_jwt_secret

  setup(function()
    spec_helper.prepare_db()
    local fixtures = spec_helper.insert_fixtures {
      api = {
        {name = "tests-jwt", request_host = "jwt.com", upstream_url = "http://mockbin.com"},
        {name = "tests-jwt2", request_host = "jwt2.com", upstream_url = "http://mockbin.com"},
        {name = "tests-jwt3", request_host = "jwt3.com", upstream_url = "http://mockbin.com"},
        {name = "tests-jwt4", request_host = "jwt4.com", upstream_url = "http://mockbin.com"},
        {name = "tests-jwt5", request_host = "jwt5.com", upstream_url = "http://mockbin.com"}
      },
      consumer = {
        {username = "jwt_tests_consumer"},
        {username = "jwt_tests_base64_consumer"}
      },
      plugin = {
        {name = "jwt", config = {}, __api = 1},
        {name = "jwt", config = {uri_param_names = {"token", "jwt"}}, __api = 2},
        {name = "jwt", config = {claims_to_verify = {"nbf", "exp"}}, __api = 3},
        {name = "jwt", config = {secret_key_field = "aud"}, __api = 4},
        {name = "jwt", config = {secret_is_base64 = true}, __api = 5}
      },
      jwt_secret = {
        {__consumer = 1},
        {__consumer = 2}
      }
    }

    jwt_secret = fixtures.jwt_secret[1]
    base64_jwt_secret = fixtures.jwt_secret[2]
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  it("should return 401 Unauthorized if no JWT is found in the request", function()
    local _, status = http_client.get(STUB_GET_URL, nil, {host = "jwt.com"})
    assert.equal(401, status)
  end)

  it("should return return 401 Unauthorized if the claims do not contain the key to identify a secret", function()
    local jwt = jwt_encoder.encode(PAYLOAD, "foo")
    local authorization = "Bearer "..jwt
    local response, status = http_client.get(STUB_GET_URL, nil, {host = "jwt.com", authorization = authorization})
    assert.equal(401, status)
    local body = json.decode(response)
    assert.equal("No mandatory 'iss' in claims", body.message)
  end)

  it("should return 403 Forbidden if the iss does not match a credential", function()
    PAYLOAD.iss = "123456789"
    local jwt = jwt_encoder.encode(PAYLOAD, jwt_secret.secret)
    local authorization = "Bearer "..jwt
    local response, status = http_client.get(STUB_GET_URL, nil, {host = "jwt.com", authorization = authorization})
    assert.equal(403, status)
    local body = json.decode(response)
    assert.equal("No credentials found for given 'iss'", body.message)
  end)

  it("should return 403 Forbidden if the signature is invalid", function()
    PAYLOAD.iss = jwt_secret.key
    local jwt = jwt_encoder.encode(PAYLOAD, "foo")
    local authorization = "Bearer "..jwt
    local response, status = http_client.get(STUB_GET_URL, nil, {host = "jwt.com", authorization = authorization})
    assert.equal(403, status)
    local body = json.decode(response)
    assert.equal("Invalid signature", body.message)
  end)

  it("should proxy the request with token and consumer headers if it was verified", function()
    PAYLOAD.iss = jwt_secret.key
    local jwt = jwt_encoder.encode(PAYLOAD, jwt_secret.secret)
    local authorization = "Bearer "..jwt
    local response, status = http_client.get(STUB_GET_URL, nil, {host = "jwt.com", authorization = authorization})
    assert.equal(200, status)
    local body = json.decode(response)
    assert.equal(authorization, body.headers.authorization)
    assert.equal("jwt_tests_consumer", body.headers["x-consumer-username"])
  end)

  it("should proxy the request if secret key is stored in a field other than iss", function()
    PAYLOAD.aud = jwt_secret.key
    local jwt = jwt_encoder.encode(PAYLOAD, jwt_secret.secret)
    local authorization = "Bearer "..jwt
    local response, status = http_client.get(STUB_GET_URL, nil, {host = "jwt4.com", authorization = authorization})
    assert.equal(200, status)
    local body = json.decode(response)
    assert.equal(authorization, body.headers.authorization)
    assert.equal("jwt_tests_consumer", body.headers["x-consumer-username"])
  end)

  it("should proxy the request if secret is base64", function()
    PAYLOAD.iss = base64_jwt_secret.key
    local original_secret = base64_jwt_secret.secret
    local base64_secret = base64.encode(base64_jwt_secret.secret)
    local base_url = spec_helper.API_URL.."/consumers/jwt_tests_consumer/jwt/"..base64_jwt_secret.id
    http_client.patch(base_url, {key = base64_jwt_secret.key, secret = base64_secret})

    local jwt = jwt_encoder.encode(PAYLOAD, original_secret)
    local authorization = "Bearer "..jwt
    local response, status = http_client.get(STUB_GET_URL, nil, {host = "jwt5.com", authorization = authorization})
    assert.equal(200, status)
    local body = json.decode(response)
    assert.equal(authorization, body.headers.authorization)
    assert.equal("jwt_tests_consumer", body.headers["x-consumer-username"])
  end)

  it("should find the JWT if given in URL parameters", function()
    PAYLOAD.iss = jwt_secret.key
    local jwt = jwt_encoder.encode(PAYLOAD, jwt_secret.secret)
    local _, status = http_client.get(STUB_GET_URL.."?jwt="..jwt, nil, {host = "jwt.com"})
    assert.equal(200, status)
  end)

  it("should find the JWT if given in a custom URL parameter", function()
    PAYLOAD.iss = jwt_secret.key
    local jwt = jwt_encoder.encode(PAYLOAD, jwt_secret.secret)
    local _, status = http_client.get(STUB_GET_URL.."?token="..jwt, nil, {host = "jwt2.com"})
    assert.equal(200, status)
  end)

  describe("JWT private claims checks", function()

    it("should require the checked fields to be in the claims", function()
      local payload = {
        iss = jwt_secret.key
      }
      local jwt = jwt_encoder.encode(payload, jwt_secret.secret)
      local res, status = http_client.get(STUB_GET_URL.."?jwt="..jwt, nil, {host = "jwt3.com"})
      assert.equal(403, status)
      assert.equal('{"nbf":"must be a number","exp":"must be a number"}\n', res)
    end)

    it("should check if the fields are valid", function()
      local payload = {
        iss = jwt_secret.key,
        exp = os.time() - 10,
        nbf = os.time() - 10
      }
      local jwt = jwt_encoder.encode(payload, jwt_secret.secret)
      local res, status = http_client.get(STUB_GET_URL.."?jwt="..jwt, nil, {host = "jwt3.com"})
      assert.equal(403, status)
      assert.equal('{"exp":"token expired"}\n', res)
    end)

  end)
end)
