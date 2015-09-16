local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local json = require "cjson"
local jwt = require "luajwt"

local STUB_GET_URL = spec_helper.STUB_GET_URL
local STUB_POST_URL = spec_helper.STUB_POST_URL

local PAYLOAD = {
  iss = "12345678",
  nbf = os.time(),
  exp = os.time() + 3600
}

describe("JWT access", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        {name = "tests jwt", public_dns = "jwt.com", target_url = "http://mockbin.com"},
        {name = "tests jwt2", public_dns = "jwt2.com", target_url = "http://mockbin.com"}
      },
      consumer = {
        {username = "jwt_tests_consumer"}
      },
      plugin = {
        {name = "jwt", config = {}, __api = 1},
        {name = "jwt", config = {uri_param_names = {"token", "jwt"}, key_claim_names = {"key", "username"}}, __api = 2}
      },
      jwtauth_secret = {
        {__consumer = 1}
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  it("should return 401 Unauthorized if no JWT is found in the request", function()

  end)

  it("should return return 401 Unauthorized if the claims do not contain the key to identify a secret", function()

  end)

  it("should return 403 Forbidden if the signature is invalid", function()

  end)

  -- Test against JWT specific use cases (invalid exptime etc)

  it("should proxy the request with token and consumer headers if it was verified", function()
    -- test against mockbin request
  end)

end)
