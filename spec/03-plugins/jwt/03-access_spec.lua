local helpers = require "spec.helpers"
local cjson = require "cjson"
local jwt_encoder = require "kong.plugins.jwt.jwt_parser"
local fixtures = require "spec.03-plugins.jwt.fixtures"
local base64 = require "base64"

local PAYLOAD = {
  iss = nil,
  nbf = os.time(),
  iat = os.time(),
  exp = os.time() + 3600
}

describe("JWT access", function()
  local jwt_secret, base64_jwt_secret, rsa_jwt_secret_1, rsa_jwt_secret_2
  local proxy_client, admin_client

  setup(function()
    helpers.dao:truncate_tables()

    local api1 = assert(helpers.dao.apis:insert {name = "tests-jwt1", request_host = "jwt.com", upstream_url = "http://mockbin.com"})
    local api2 = assert(helpers.dao.apis:insert {name = "tests-jwt2", request_host = "jwt2.com", upstream_url = "http://mockbin.com"})
    local api3 = assert(helpers.dao.apis:insert {name = "tests-jwt3", request_host = "jwt3.com", upstream_url = "http://mockbin.com"})
    local api4 = assert(helpers.dao.apis:insert {name = "tests-jwt4", request_host = "jwt4.com", upstream_url = "http://mockbin.com"})
    local api5 = assert(helpers.dao.apis:insert {name = "tests-jwt5", request_host = "jwt5.com", upstream_url = "http://mockbin.com"})

    local consumer1 = assert(helpers.dao.consumers:insert {username = "jwt_tests_consumer"})
    local consumer2 = assert(helpers.dao.consumers:insert {username = "jwt_tests_base64_consumer"})
    local consumer3 = assert(helpers.dao.consumers:insert {username = "jwt_tests_rsa_consumer_1"})
    local consumer4 = assert(helpers.dao.consumers:insert {username = "jwt_tests_rsa_consumer_2"})

    assert(helpers.dao.plugins:insert {name = "jwt", config = {}, api_id = api1.id})
    assert(helpers.dao.plugins:insert {name = "jwt", config = {uri_param_names = {"token", "jwt"}}, api_id = api2.id})
    assert(helpers.dao.plugins:insert {name = "jwt", config = {claims_to_verify = {"nbf", "exp"}}, api_id = api3.id})
    assert(helpers.dao.plugins:insert {name = "jwt", config = {key_claim_name = "aud"}, api_id = api4.id})
    assert(helpers.dao.plugins:insert {name = "jwt", config = {secret_is_base64 = true}, api_id = api5.id})

    jwt_secret = assert(helpers.dao.jwt_secrets:insert {consumer_id = consumer1.id})
    base64_jwt_secret = assert(helpers.dao.jwt_secrets:insert {consumer_id = consumer2.id})
    rsa_jwt_secret_1 = assert(helpers.dao.jwt_secrets:insert {
      consumer_id = consumer3.id,
      algorithm = "RS256",
      rsa_public_key = fixtures.rs256_public_key
    })
    rsa_jwt_secret_2 = assert(helpers.dao.jwt_secrets:insert {
      consumer_id = consumer4.id,
      algorithm = "RS256",
      rsa_public_key = fixtures.rs256_public_key
    })

    assert(helpers.start_kong())
    proxy_client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.proxy_port))
    admin_client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.admin_port))
  end)

  teardown(function()
    if proxy_client then proxy_client:close() end
    if admin_client then admin_client:close() end
    helpers.stop_kong()
  end)

  describe("refusals", function()
    it("returns 401 Unauthorized if no JWT is found in the request", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "jwt.com"
        }
      })
      assert.res_status(401, res)
    end)
    it("returns 401 if the claims do not contain the key to identify a secret", function()
      local jwt = jwt_encoder.encode(PAYLOAD, "foo")
      local authorization = "Bearer "..jwt
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Authorization"] = authorization,
          ["Host"] = "jwt.com"
        }
      })
      local body = assert.res_status(401, res)
      assert.equal([[{"message":"No mandatory 'iss' in claims"}]], body)
    end)
    it("returns 403 Forbidden if the iss does not match a credential", function()
      PAYLOAD.iss = "123456789"
      local jwt = jwt_encoder.encode(PAYLOAD, jwt_secret.secret)
      local authorization = "Bearer "..jwt
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Authorization"] = authorization,
          ["Host"] = "jwt.com"
        }
      })
      local body = assert.res_status(403, res)
      assert.equal([[{"message":"No credentials found for given 'iss'"}]], body)
    end)
    it("returns 403 Forbidden if the signature is invalid", function()
      PAYLOAD.iss = jwt_secret.key
      local jwt = jwt_encoder.encode(PAYLOAD, "foo")
      local authorization = "Bearer "..jwt
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Authorization"] = authorization,
          ["Host"] = "jwt.com"
        }
      })
      local body = assert.res_status(403, res)
      assert.equal([[{"message":"Invalid signature"}]], body)
    end)
    it("returns 403 Forbidden if the alg does not match the credential", function()
      local header = {typ = "JWT", alg = 'RS256'}
      local jwt = jwt_encoder.encode(PAYLOAD, jwt_secret.secret, 'HS256', header)
      local authorization = "Bearer "..jwt
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Authorization"] = authorization,
          ["Host"] = "jwt.com"
        }
      })
      local body = assert.res_status(403, res)
      assert.equal([[{"message":"Invalid algorithm"}]], body)
    end)
  end)

  describe("HS256", function()
    it("proxies the request with token and consumer headers if it was verified", function()
      PAYLOAD.iss = jwt_secret.key
      local jwt = jwt_encoder.encode(PAYLOAD, jwt_secret.secret)
      local authorization = "Bearer "..jwt
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Authorization"] = authorization,
          ["Host"] = "jwt.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal(authorization, body.headers.authorization)
      assert.equal("jwt_tests_consumer", body.headers["x-consumer-username"])
    end)
    it("proxies the request if secret key is stored in a field other than iss", function()
      PAYLOAD.aud = jwt_secret.key
      local jwt = jwt_encoder.encode(PAYLOAD, jwt_secret.secret)
      local authorization = "Bearer "..jwt
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Authorization"] = authorization,
          ["Host"] = "jwt4.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal(authorization, body.headers.authorization)
      assert.equal("jwt_tests_consumer", body.headers["x-consumer-username"])
    end)
    it("proxies the request if secret is base64", function()
      PAYLOAD.iss = base64_jwt_secret.key
      local original_secret = base64_jwt_secret.secret
      local base64_secret = base64.encode(base64_jwt_secret.secret)
      assert(admin_client:send {
        method = "PATCH",
        path = "/consumers/jwt_tests_consumer/jwt/"..base64_jwt_secret.id,
        body = {
          key = base64_jwt_secret.key,
          secret = base64_secret},
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      local jwt = jwt_encoder.encode(PAYLOAD, original_secret)
      local authorization = "Bearer "..jwt
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Authorization"] = authorization,
          ["Host"] = "jwt5.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal(authorization, body.headers.authorization)
      assert.equal("jwt_tests_consumer", body.headers["x-consumer-username"])
    end)
    it("finds the JWT if given in URL parameters", function()
      PAYLOAD.iss = jwt_secret.key
      local jwt = jwt_encoder.encode(PAYLOAD, jwt_secret.secret)
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request/?jwt="..jwt,
        headers = {
          ["Host"] = "jwt.com"
        }
      })
      assert.res_status(200, res)
    end)
    it("finds the JWT if given in a custom URL parameter", function()
      PAYLOAD.iss = jwt_secret.key
      local jwt = jwt_encoder.encode(PAYLOAD, jwt_secret.secret)
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request/?token="..jwt,
        headers = {
          ["Host"] = "jwt2.com"
        }
      })
      assert.res_status(200, res)
    end)
  end)

  describe("RS256", function()
    it("verifies JWT", function()
      PAYLOAD.iss = rsa_jwt_secret_1.key
      local jwt = jwt_encoder.encode(PAYLOAD, fixtures.rs256_private_key, 'RS256')
      local authorization = "Bearer "..jwt
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Authorization"] = authorization,
          ["Host"] = "jwt.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal(authorization, body.headers.authorization)
      assert.equal("jwt_tests_rsa_consumer_1", body.headers["x-consumer-username"])
    end)
    it("identifies Consumer", function()
      PAYLOAD.iss = rsa_jwt_secret_2.key
      local jwt = jwt_encoder.encode(PAYLOAD, fixtures.rs256_private_key, 'RS256')
      local authorization = "Bearer "..jwt
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Authorization"] = authorization,
          ["Host"] = "jwt.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal(authorization, body.headers.authorization)
      assert.equal("jwt_tests_rsa_consumer_2", body.headers["x-consumer-username"])
    end)
  end)

  describe("JWT private claims checks", function()
    it("requires the checked fields to be in the claims", function()
      local payload = {
        iss = jwt_secret.key
      }
      local jwt = jwt_encoder.encode(payload, jwt_secret.secret)
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request/?jwt="..jwt,
        headers = {
          ["Host"] = "jwt3.com"
        }
      })
      local body = assert.res_status(403, res)
      assert.equal('{"nbf":"must be a number","exp":"must be a number"}', body)
    end)
    it("checks if the fields are valid", function()
      local payload = {
        iss = jwt_secret.key,
        exp = os.time() - 10,
        nbf = os.time() - 10
      }
      local jwt = jwt_encoder.encode(payload, jwt_secret.secret)
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request/?jwt="..jwt,
        headers = {
          ["Host"] = "jwt3.com"
        }
      })
      local body = assert.res_status(403, res)
      assert.equal('{"exp":"token expired"}', body)
    end)
  end)
end)
