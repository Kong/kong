local cjson = require "cjson"
local helpers = require "spec.helpers"
local fixtures = require "spec-old-api.03-plugins.17-jwt.fixtures"
local jwt_encoder = require "kong.plugins.jwt.jwt_parser"
local utils = require "kong.tools.utils"

local PAYLOAD = {
  iss = nil,
  nbf = os.time(),
  iat = os.time(),
  exp = os.time() + 3600
}

describe("Plugin: jwt (access)", function()
  local jwt_secret, base64_jwt_secret, rsa_jwt_secret_1, rsa_jwt_secret_2, rsa_jwt_secret_3
  local proxy_client, admin_client

  setup(function()
    local bp, db, dao = helpers.get_db_utils()

    local apis = {}

    for i = 1, 9 do
      apis[i] = assert(dao.apis:insert({
        name         = "tests-jwt" .. i,
        hosts        = { "jwt" .. i .. ".com" },
        upstream_url = helpers.mock_upstream_url,
      }))
    end

    local cdao = bp.consumers
    local consumer1 = cdao:insert({ username = "jwt_tests_consumer" })
    local consumer2 = cdao:insert({ username = "jwt_tests_base64_consumer" })
    local consumer3 = cdao:insert({ username = "jwt_tests_rsa_consumer_1" })
    local consumer4 = cdao:insert({ username = "jwt_tests_rsa_consumer_2" })
    local consumer5 = cdao:insert({ username = "jwt_tests_rsa_consumer_5" })
    local anonymous_user = cdao:insert({ username = "no-body" })

    local pdao = db.plugins
    assert(pdao:insert({ name   = "jwt",
                         api = { id = apis[1].id },
                         config = {},
                       }))
    assert(pdao:insert({ name   = "jwt",
                         api = { id = apis[2].id },
                         config = { uri_param_names = { "token", "jwt" } },
                       }))
    assert(pdao:insert({ name   = "jwt",
                         api = { id = apis[3].id },
                         config = { claims_to_verify = {"nbf", "exp"} },
                       }))
    assert(pdao:insert({ name   = "jwt",
                         api = { id = apis[4].id },
                         config = { key_claim_name = "aud" },
                       }))
    assert(pdao:insert({ name   = "jwt",
                         api = { id = apis[5].id },
                         config = { secret_is_base64 = true },
                       }))
    assert(pdao:insert({ name   = "jwt",
                         api = { id = apis[6].id },
                         config = { anonymous = anonymous_user.id },
                       }))
    assert(pdao:insert({ name   = "jwt",
                         api = { id = apis[7].id },
                         config = { anonymous = utils.uuid() },
                       }))
    assert(pdao:insert({ name   = "jwt",
                         api = { id = apis[8].id },
                         config = { run_on_preflight = false },
                       }))
    assert(pdao:insert({ name   = "jwt",
                         api = { id = apis[9].id },
                         config = { cookie_names = { "silly", "crumble" } },
                       }))

    jwt_secret = bp.jwt_secrets:insert { consumer = { id = consumer1.id } }
    base64_jwt_secret = bp.jwt_secrets:insert { consumer = { id = consumer2.id } }
    rsa_jwt_secret_1 = bp.jwt_secrets:insert {
      consumer = { id = consumer3.id },
      algorithm = "RS256",
      rsa_public_key = fixtures.rs256_public_key
    }
    rsa_jwt_secret_2 = bp.jwt_secrets:insert {
      consumer = { id = consumer4.id },
      algorithm = "RS256",
      rsa_public_key = fixtures.rs256_public_key
    }
    rsa_jwt_secret_3 = bp.jwt_secrets:insert {
      consumer = { id = consumer5.id },
      algorithm = "RS512",
      rsa_public_key = fixtures.rs512_public_key
    }

    assert(helpers.start_kong {
      real_ip_header    = "X-Forwarded-For",
      real_ip_recursive = "on",
      trusted_ips       = "0.0.0.0/0, ::/0",
      nginx_conf        = "spec/fixtures/custom_nginx.template",
    })
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
        method  = "GET",
        path    = "/request",
        headers = {
          ["Host"] = "jwt1.com",
        }
      })
      assert.res_status(401, res)
    end)
    it("returns 401 if the claims do not contain the key to identify a secret", function()
      local jwt = jwt_encoder.encode(PAYLOAD, "foo")
      local authorization = "Bearer " .. jwt
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Authorization"] = authorization,
          ["Host"]          = "jwt1.com",
        }
      })
      local body = assert.res_status(401, res)
      local json = cjson.decode(body)
      assert.same({ message = "No mandatory 'iss' in claims" }, json)
    end)
    it("returns 403 Forbidden if the iss does not match a credential", function()
      PAYLOAD.iss = "123456789"
      local jwt = jwt_encoder.encode(PAYLOAD, jwt_secret.secret)
      local authorization = "Bearer " .. jwt
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Authorization"] = authorization,
          ["Host"]          = "jwt1.com",
        }
      })
      local body = assert.res_status(403, res)
      local json = cjson.decode(body)
      assert.same({ message = "No credentials found for given 'iss'" }, json)
    end)
    it("returns 403 Forbidden if the signature is invalid", function()
      PAYLOAD.iss = jwt_secret.key
      local jwt = jwt_encoder.encode(PAYLOAD, "foo")
      local authorization = "Bearer " .. jwt
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Authorization"] = authorization,
          ["Host"]          = "jwt1.com",
        }
      })
      local body = assert.res_status(403, res)
      local json = cjson.decode(body)
      assert.same({ message = "Invalid signature" }, json)
    end)
    it("returns 403 Forbidden if the alg does not match the credential", function()
      local header = {typ = "JWT", alg = 'RS256'}
      local jwt = jwt_encoder.encode(PAYLOAD, jwt_secret.secret, 'HS256', header)
      local authorization = "Bearer " .. jwt
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Authorization"] = authorization,
          ["Host"]          = "jwt1.com",
        }
      })
      local body = assert.res_status(403, res)
      local json = cjson.decode(body)
      assert.same({ message = "Invalid algorithm" }, json)
    end)
    it("returns 200 on OPTIONS requests if run_on_preflight is false", function()
      local res = assert(proxy_client:send {
        method = "OPTIONS",
        path = "/request",
        headers = {
          ["Host"] = "jwt8.com"
        }
      })
      assert.res_status(200, res)
    end)
    it("returns Unauthorized on OPTIONS requests if run_on_preflight is true", function()
      local res = assert(proxy_client:send {
        method = "OPTIONS",
        path = "/request",
        headers = {
          ["Host"] = "jwt1.com"
        }
      })
      local body = assert.res_status(401, res)
      assert.equal([[{"message":"Unauthorized"}]], body)
    end)
  end)

  describe("HS256", function()
    it("proxies the request with token and consumer headers if it was verified", function()
      PAYLOAD.iss = jwt_secret.key
      local jwt = jwt_encoder.encode(PAYLOAD, jwt_secret.secret)
      local authorization = "Bearer " .. jwt
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Authorization"] = authorization,
          ["Host"]          = "jwt1.com",
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
      local authorization = "Bearer " .. jwt
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
        path = "/consumers/jwt_tests_base64_consumer/jwt/" .. base64_jwt_secret.id,
        body = {
          key = base64_jwt_secret.key,
          secret = base64_secret},
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(200, res)

      local jwt = jwt_encoder.encode(PAYLOAD, original_secret)
      local authorization = "Bearer " .. jwt
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
        method  = "GET",
        path    = "/request/?jwt=" .. jwt,
        headers = {
          ["Host"] = "jwt1.com",
        }
      })
      assert.res_status(200, res)
    end)
    it("returns 200 the JWT is found in the cookie crumble", function()
      PAYLOAD.iss = jwt_secret.key
      local jwt = jwt_encoder.encode(PAYLOAD, jwt_secret.secret)
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Host"] = "jwt9.com",
          ["Cookie"] = "crumble=" .. jwt .. "; path=/;domain=.jwt9.com",
        }
      })
      assert.res_status(200, res)
    end)
    it("returns 200 if the JWT is found in the cookie silly", function()
      PAYLOAD.iss = jwt_secret.key
      local jwt = jwt_encoder.encode(PAYLOAD, jwt_secret.secret)
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Host"] = "jwt9.com",
          ["Cookie"] = "silly=" .. jwt .. "; path=/;domain=.jwt9.com",
        }
      })
      assert.res_status(200, res)
    end)
    it("returns 403 if the JWT found in the cookie does not match a credential", function()
      PAYLOAD.iss = "incorrect-issuer"
      local jwt = jwt_encoder.encode(PAYLOAD, jwt_secret.secret)
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Host"] = "jwt9.com",
          ["Cookie"] = "silly=" .. jwt .. "; path=/;domain=.jwt9.com",
        }
      })
      local body = assert.res_status(403, res)
      local json = cjson.decode(body)
      assert.same({ message = "No credentials found for given 'iss'" }, json)
    end)
    it("returns a 401 if the JWT in the cookie is corrupted", function()
      PAYLOAD.iss = jwt_secret.key
      local jwt = "no-way-this-works" .. jwt_encoder.encode(PAYLOAD, jwt_secret.secret)
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Host"] = "jwt9.com",
          ["Cookie"] = "silly=" .. jwt .. "; path=/;domain=.jwt9.com",
        }
      })
      local body = assert.res_status(401, res)
      assert.equal([[{"message":"Bad token; invalid JSON"}]], body)
    end)
    it("reports a 200 without cookies but with a JWT token in the Authorization header", function()
      PAYLOAD.iss = jwt_secret.key
      local jwt = jwt_encoder.encode(PAYLOAD, jwt_secret.secret)
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Host"] = "jwt9.com",
          ["Authorization"] = "Bearer " .. jwt,
        }
      })
      assert.res_status(200, res)
    end)
    it("returns 401 if no JWT tokens are found in cookies or Authorization header", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Host"] = "jwt9.com",
        }
      })
      assert.res_status(401, res)
    end)
    it("finds the JWT if given in a custom URL parameter", function()
      PAYLOAD.iss = jwt_secret.key
      local jwt = jwt_encoder.encode(PAYLOAD, jwt_secret.secret)
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request/?token=" .. jwt,
        headers = {
          ["Host"] = "jwt2.com",
        }
      })
      assert.res_status(200, res)
    end)
  end)

  describe("RS256", function()
    it("verifies JWT", function()
      PAYLOAD.iss = rsa_jwt_secret_1.key
      local jwt = jwt_encoder.encode(PAYLOAD, fixtures.rs256_private_key, 'RS256')
      local authorization = "Bearer " .. jwt
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Authorization"] = authorization,
          ["Host"]          = "jwt1.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal(authorization, body.headers.authorization)
      assert.equal("jwt_tests_rsa_consumer_1", body.headers["x-consumer-username"])
    end)
    it("identifies Consumer", function()
      PAYLOAD.iss = rsa_jwt_secret_2.key
      local jwt = jwt_encoder.encode(PAYLOAD, fixtures.rs256_private_key, 'RS256')
      local authorization = "Bearer " .. jwt
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Authorization"] = authorization,
          ["Host"]          = "jwt1.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal(authorization, body.headers.authorization)
      assert.equal("jwt_tests_rsa_consumer_2", body.headers["x-consumer-username"])
    end)
  end)

describe("RS512", function()
    it("verifies JWT", function()
      PAYLOAD.iss = rsa_jwt_secret_3.key
      local jwt = jwt_encoder.encode(PAYLOAD, fixtures.rs512_private_key, "RS512")
      local authorization = "Bearer " .. jwt
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Authorization"] = authorization,
          ["Host"]          = "jwt1.com",
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal(authorization, body.headers.authorization)
      assert.equal("jwt_tests_rsa_consumer_5", body.headers["x-consumer-username"])
    end)
    it("identifies Consumer", function()
      PAYLOAD.iss = rsa_jwt_secret_3.key
      local jwt = jwt_encoder.encode(PAYLOAD, fixtures.rs512_private_key, "RS512")
      local authorization = "Bearer " .. jwt
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Authorization"] = authorization,
          ["Host"]          = "jwt1.com",
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal(authorization, body.headers.authorization)
      assert.equal("jwt_tests_rsa_consumer_5", body.headers["x-consumer-username"])
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
        path = "/request/?jwt=" .. jwt,
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
        path = "/request/?jwt=" .. jwt,
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
        path = "/request/?jwt=" .. jwt,
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
      local authorization = "Bearer " .. jwt
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
    local bp, db, dao = helpers.get_db_utils()

    local api1 = assert(dao.apis:insert {
      name         = "api-1",
      hosts        = { "logical-and.com" },
      upstream_url = helpers.mock_upstream_url .. "/request",
    })
    assert(db.plugins:insert {
      name   = "jwt",
      api = { id = api1.id },
    })
    assert(db.plugins:insert {
      name   = "key-auth",
      api = { id = api1.id },
    })

    anonymous = bp.consumers:insert {
      username = "Anonymous",
    }
    user1 = bp.consumers:insert {
      username = "Mickey",
    }
    user2 = bp.consumers:insert {
      username = "Aladdin",
    }

    local api2 = assert(dao.apis:insert {
      name         = "api-2",
      hosts        = { "logical-or.com" },
      upstream_url = helpers.mock_upstream_url .. "/request",
    })
    assert(db.plugins:insert {
      name   = "jwt",
      api = { id = api2.id },
      config = {
        anonymous = anonymous.id,
      },
    })
    assert(db.plugins:insert {
      name   = "key-auth",
      api = { id = api2.id },
      config = {
        anonymous = anonymous.id,
      },
    })

    bp.keyauth_credentials:insert {
      key      = "Mouse",
      consumer = { id = user1.id },
    }

    local jwt_secret = bp.jwt_secrets:insert {
      consumer = { id = user2.id },
    }
    PAYLOAD.iss = jwt_secret.key
    jwt_token   = "Bearer " .. jwt_encoder.encode(PAYLOAD, jwt_secret.secret)

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
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
