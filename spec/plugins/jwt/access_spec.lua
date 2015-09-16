local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local json = require "cjson"
local lua_jwt = require "luajwt"

local STUB_GET_URL = spec_helper.STUB_GET_URL

local PAYLOAD = {
  iss = "12345678",
  nbf = os.time(),
  exp = os.time() + 3600
}

describe("JWT access", function()
  local jwt_secret

  setup(function()
    spec_helper.prepare_db()
    local fixtures = spec_helper.insert_fixtures {
      api = {
        {name = "tests jwt", inbound_dns = "jwt.com", upstream_url = "http://mockbin.com"},
        {name = "tests jwt2", inbound_dns = "jwt2.com", upstream_url = "http://mockbin.com"}
      },
      consumer = {
        {username = "jwt_tests_consumer"}
      },
      plugin = {
        {name = "jwt", config = {}, __api = 1},
        {name = "jwt", config = {uri_param_names = {"token", "jwt"}, key_claim_names = {"key", "username"}}, __api = 2}
      },
      jwt_secret = {
        {__consumer = 1}
      }
    }

    jwt_secret = fixtures.jwt_secret[1]
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
    local jwt = lua_jwt.encode(PAYLOAD, "foo")
    local authorization = "Bearer "..jwt
    local response, status = http_client.get(STUB_GET_URL, nil, {host = "jwt.com", authorization = authorization})
    assert.equal(401, status)
    local body = json.decode(response)
    assert.equal("No key in claims", body.message)
  end)

  it("should return 403 Forbidden if the signature is invalid", function()
    PAYLOAD.key = jwt_secret.key
    local jwt = lua_jwt.encode(PAYLOAD, "foo")
    local authorization = "Bearer "..jwt
    local response, status = http_client.get(STUB_GET_URL, nil, {host = "jwt.com", authorization = authorization})
    assert.equal(403, status)
    local body = json.decode(response)
    assert.equal("Invalid signature", body.message)
  end)

  it("should proxy the request with token and consumer headers if it was verified", function()
    PAYLOAD.key = jwt_secret.key
    local jwt = lua_jwt.encode(PAYLOAD, jwt_secret.secret)
    local authorization = "Bearer "..jwt
    local response, status = http_client.get(STUB_GET_URL, nil, {host = "jwt.com", authorization = authorization})
    assert.equal(200, status)
    local body = json.decode(response)
    assert.equal(authorization, body.headers.authorization)
    assert.equal("jwt_tests_consumer", body.headers["x-consumer-username"])
  end)

  it("should find the JWT if given in URL parameters", function()
    PAYLOAD.key = jwt_secret.key
    local jwt = lua_jwt.encode(PAYLOAD, jwt_secret.secret)
    local _, status = http_client.get(STUB_GET_URL.."?jwt="..jwt, nil, {host = "jwt.com"})
    assert.equal(200, status)
  end)

  describe("Custom parameter and claim names", function()

    it("should find the JWT if given in a custom URL parameter", function()
      PAYLOAD.key = jwt_secret.key
      local jwt = lua_jwt.encode(PAYLOAD, jwt_secret.secret)
      local _, status = http_client.get(STUB_GET_URL.."?token="..jwt, nil, {host = "jwt2.com"})
      assert.equal(200, status)
    end)

    it("should find the key in the claims if using a custom name", function()
      PAYLOAD.key = nil
      PAYLOAD.username = jwt_secret.key
      local jwt = lua_jwt.encode(PAYLOAD, jwt_secret.secret)
      local _, status = http_client.get(STUB_GET_URL.."?jwt="..jwt, nil, {host = "jwt2.com"})
      assert.equal(200, status)
    end)

  end)

  describe("JWT specifics", function()

  end)

end)
