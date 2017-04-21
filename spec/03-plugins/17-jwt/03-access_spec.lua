local cjson = require "cjson"
local helpers = require "spec.helpers"
local fixtures = require "spec.03-plugins.17-jwt.fixtures"
local jwt_encoder = require "kong.plugins.jwt.jwt_parser"
local utils = require "kong.tools.utils"

local PAYLOAD = {
  iss = nil,
  nbf = os.time(),
  iat = os.time(),
  exp = os.time() + 3600
}

describe("Plugin: jwt (access)", function()
  local jwt_secret, base64_jwt_secret, rsa_jwt_secret_1, rsa_jwt_secret_2
  local proxy_client, admin_client

  setup(function()
    local api1 = assert(helpers.dao.apis:insert {name = "tests-jwt1", hosts = { "jwt.com" }, upstream_url = "http://mockbin.com"})
    local api2 = assert(helpers.dao.apis:insert {name = "tests-jwt2", hosts = { "jwt2.com" }, upstream_url = "http://mockbin.com"})
    local api3 = assert(helpers.dao.apis:insert {name = "tests-jwt3", hosts = { "jwt3.com" }, upstream_url = "http://mockbin.com"})
    local api4 = assert(helpers.dao.apis:insert {name = "tests-jwt4", hosts = { "jwt4.com" }, upstream_url = "http://mockbin.com"})
    local api5 = assert(helpers.dao.apis:insert {name = "tests-jwt5", hosts = { "jwt5.com" }, upstream_url = "http://mockbin.com"})
    local api6 = assert(helpers.dao.apis:insert {name = "tests-jwt6", hosts = { "jwt6.com" }, upstream_url = "http://mockbin.com"})
    local api7 = assert(helpers.dao.apis:insert {name = "tests-jwt7", hosts = { "jwt7.com" }, upstream_url = "http://mockbin.com"})

    local consumer1 = assert(helpers.dao.consumers:insert {username = "jwt_tests_consumer"})
    local consumer2 = assert(helpers.dao.consumers:insert {username = "jwt_tests_base64_consumer"})
    local consumer3 = assert(helpers.dao.consumers:insert {username = "jwt_tests_rsa_consumer_1"})
    local consumer4 = assert(helpers.dao.consumers:insert {username = "jwt_tests_rsa_consumer_2"})
    local anonymous_user = assert(helpers.dao.consumers:insert {username = "no-body"})

    assert(helpers.dao.plugins:insert {name = "jwt", config = {}, api_id = api1.id})
    assert(helpers.dao.plugins:insert {name = "jwt", config = {uri_param_names = {"token", "jwt"}}, api_id = api2.id})
    assert(helpers.dao.plugins:insert {name = "jwt", config = {claims_to_verify = {"nbf", "exp"}}, api_id = api3.id})
    assert(helpers.dao.plugins:insert {name = "jwt", config = {key_claim_name = "aud"}, api_id = api4.id})
    assert(helpers.dao.plugins:insert {name = "jwt", config = {secret_is_base64 = true}, api_id = api5.id})
    assert(helpers.dao.plugins:insert {name = "jwt", config = {anonymous = anonymous_user.id}, api_id = api6.id})
    assert(helpers.dao.plugins:insert {name = "jwt", config = {anonymous = utils.uuid()}, api_id = api7.id})

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
    proxy_client = helpers.proxy_client()
    admin_client = helpers.admin_client()
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
      local json = cjson.decode(body)
      assert.same({ message = "No mandatory 'iss' in claims" }, json)
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
      local json = cjson.decode(body)
      assert.same({ message = "No credentials found for given 'iss'" }, json)
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
      local json = cjson.decode(body)
      assert.same({ message = "Invalid signature" }, json)
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
      local json = cjson.decode(body)
      assert.same({ message = "Invalid algorithm" }, json)
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
      assert.is_nil(body.headers["x-anonymous-consumer"])
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
      local base64_secret = ngx.encode_base64(base64_jwt_secret.secret)
      local res = assert(admin_client:send {
        method = "PATCH",
        path = "/consumers/jwt_tests_base64_consumer/jwt/"..base64_jwt_secret.id,
        body = {
          key = base64_jwt_secret.key,
          secret = base64_secret},
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(200, res)

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
      assert.equal("jwt_tests_base64_consumer", body.headers["x-consumer-username"])
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
      local body = assert.res_status(401, res)
      assert.equal('{"nbf":"must be a number","exp":"must be a number"}', body)
    end)
    it("checks if the fields are valid: `exp` claim", function()
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
      local body = assert.res_status(401, res)
      assert.equal('{"exp":"token expired"}', body)
    end)
    it("checks if the fields are valid: `nbf` claim", function()
      local payload = {
        iss = jwt_secret.key,
        exp = os.time() + 10,
        nbf = os.time() + 5
      }
      local jwt = jwt_encoder.encode(payload, jwt_secret.secret)
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request/?jwt="..jwt,
        headers = {
          ["Host"] = "jwt3.com"
        }
      })
      local body = assert.res_status(401, res)
      assert.equal('{"nbf":"token not valid yet"}', body)
    end)
  end)

  describe("config.anonymous", function()
    it("works with right credentials and anonymous", function()
      PAYLOAD.iss = jwt_secret.key
      local jwt = jwt_encoder.encode(PAYLOAD, jwt_secret.secret)
      local authorization = "Bearer "..jwt
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Authorization"] = authorization,
          ["Host"] = "jwt6.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal('jwt_tests_consumer', body.headers["x-consumer-username"])
      assert.is_nil(body.headers["x-anonymous-consumer"])
    end)
    it("works with wrong credentials and anonymous", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "jwt6.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal('true', body.headers["x-anonymous-consumer"])
      assert.equal('no-body', body.headers["x-consumer-username"])
    end)
    it("errors when anonymous user doesn't exist", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "jwt7.com"
        }
      })
      assert.response(res).has.status(500)
    end)
  end)
end)


describe("Plugin: jwt (access)", function()

  local client, user1, user2, anonymous, jwt_token

  setup(function()
    local api1 = assert(helpers.dao.apis:insert {
      name = "api-1",
      hosts = { "logical-and.com" },
      upstream_url = "http://mockbin.org/request"
    })
    assert(helpers.dao.plugins:insert {
      name = "jwt",
      api_id = api1.id
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api1.id
    })

    anonymous = assert(helpers.dao.consumers:insert {
      username = "Anonymous"
    })
    user1 = assert(helpers.dao.consumers:insert {
      username = "Mickey"
    })
    user2 = assert(helpers.dao.consumers:insert {
      username = "Aladdin"
    })

    local api2 = assert(helpers.dao.apis:insert {
      name = "api-2",
      hosts = { "logical-or.com" },
      upstream_url = "http://mockbin.org/request"
    })
    assert(helpers.dao.plugins:insert {
      name = "jwt",
      api_id = api2.id,
      config = {
        anonymous = anonymous.id
      }
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api2.id,
      config = {
        anonymous = anonymous.id
      }
    })

    assert(helpers.dao.keyauth_credentials:insert {
      key = "Mouse",
      consumer_id = user1.id
    })

    local jwt_secret = assert(helpers.dao.jwt_secrets:insert {
      consumer_id = user2.id
    })
    PAYLOAD.iss = jwt_secret.key
    jwt_token = "Bearer "..jwt_encoder.encode(PAYLOAD, jwt_secret.secret)

    assert(helpers.start_kong())
    client = helpers.proxy_client()
  end)


  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  describe("multiple auth without anonymous, logical AND", function()

    it("passes with all credentials provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-and.com",
          ["apikey"] = "Mouse",
          ["Authorization"] = jwt_token,
        }
      })
      assert.response(res).has.status(200)
      assert.request(res).has.no.header("x-anonymous-consumer")
      local id = assert.request(res).has.header("x-consumer-id")
      assert.not_equal(id, anonymous.id)
      assert(id == user1.id or id == user2.id)
    end)

    it("fails 401, with only the first credential provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-and.com",
          ["apikey"] = "Mouse",
        }
      })
      assert.response(res).has.status(401)
    end)

    it("fails 401, with only the second credential provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-and.com",
          ["Authorization"] = jwt_token,
        }
      })
      assert.response(res).has.status(401)
    end)

    it("fails 401, with no credential provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-and.com",
        }
      })
      assert.response(res).has.status(401)
    end)

  end)

  describe("multiple auth with anonymous, logical OR", function()

    it("passes with all credentials provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-or.com",
          ["apikey"] = "Mouse",
          ["Authorization"] = jwt_token,
        }
      })
      assert.response(res).has.status(200)
      assert.request(res).has.no.header("x-anonymous-consumer")
      local id = assert.request(res).has.header("x-consumer-id")
      assert.not_equal(id, anonymous.id)
      assert(id == user1.id or id == user2.id)
    end)

    it("passes with only the first credential provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-or.com",
          ["apikey"] = "Mouse",
        }
      })
      assert.response(res).has.status(200)
      assert.request(res).has.no.header("x-anonymous-consumer")
      local id = assert.request(res).has.header("x-consumer-id")
      assert.not_equal(id, anonymous.id)
      assert.equal(user1.id, id)
    end)

    it("passes with only the second credential provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-or.com",
          ["Authorization"] = jwt_token,
        }
      })
      assert.response(res).has.status(200)
      assert.request(res).has.no.header("x-anonymous-consumer")
      local id = assert.request(res).has.header("x-consumer-id")
      assert.not_equal(id, anonymous.id)
      assert.equal(user2.id, id)
    end)

    it("passes with no credential provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-or.com",
        }
      })
      assert.response(res).has.status(200)
      assert.request(res).has.header("x-anonymous-consumer")
      local id = assert.request(res).has.header("x-consumer-id")
      assert.equal(id, anonymous.id)
    end)

  end)

end)
