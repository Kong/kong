-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ngx            = ngx
local jwt            = require "resty.jwt"
local cache          = require("kong.plugins.upstream-oauth.cache")
local helpers        = require "spec.helpers"
local PLUGIN_NAME    = "upstream-oauth"

local REDIS_HOST     = helpers.redis_host
local REDIS_PORT     = 6379
local REDIS_DATABASE = 2


local KEYCLOAK_ISSUER                                  = "https://keycloak:8443/realms/test"
local KEYCLOAK_TOKEN_ENDPOINT                          = KEYCLOAK_ISSUER .. "/protocol/openid-connect/token"

local CLIENT_CREDENTIALS_GRANT_POST_AUTH_CLIENT_ID     = "test-client-credentials-grant-post-auth"
local CLIENT_CREDENTIALS_GRANT_POST_AUTH_CLIENT_SECRET = "test-client-credentials-grant-post-auth-secret"
local CLIENT_CREDENTIALS_GRANT_JWT_AUTH_CLIENT_ID      = "test-client-credentials-grant-jwt-auth"
local CLIENT_CREDENTIALS_GRANT_JWT_AUTH_CLIENT_SECRET  = "test-client-credentials-grant-jwt-auth-secret"

local PASSWORD_GRANT_POST_AUTH_CLIENT_ID               = "test-password-grant-post-auth"
local PASSWORD_GRANT_POST_AUTH_CLIENT_SECRET           = "test-password-grant-post-auth-secret"
local PASSWORD_GRANT_JWT_AUTH_CLIENT_ID                = "test-password-grant-jwt-auth"
local PASSWORD_GRANT_JWT_AUTH_CLIENT_SECRET            = "test-password-grant-jwt-auth-secret"
local PASSWORD_GRANT_USERNAME                          = "john"
local PASSWORD_GRANT_PASSWORD                          = "doe"
local PASSWORD_GRANT_EMAIL                             = "john.doe@konghq.com"

local ACCESS_TOKEN_EXPIRY_CLIENT_ID                    = "test-access-token-expires"
local ACCESS_TOKEN_EXPIRY_CLIENT_SECRET                = "test-access-token-expires-secret"

local RS256_PUB_KEY                                    = [[
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAgUPNE71ay9S36pzW/ZQp
7rRgOLFb15ioQY/cLl2NFrDEPPS2182Jt2qY/E1XXsfyavIVT/Sqr3Iye6fkD5Vv
mllPaUjsKPSaZCibfxZ9Of8504Bn1CM7+IbsMSlSn3hJMOX3vnASQQR0TJQHamiz
Udr65u+r2eWTTLZuAMy3NVQr4z6X3hUPm70/A0rzQah4ryK2M8/+31EuXeayianY
NTi0uJsXKvIRP99wyjFpOLaqSf4nswIXOTSJ4AFVabXA1WbCZKozZGZzzLQBCUTV
oDAPFUaf0fFbdysxFNuUlmGh+wOrfZzx7Aa8htcsrRm15Xm2OWiGfsc8+NWxzOkr
dwIDAQAB
-----END PUBLIC KEY-----
]]

local function validate_authorization_header(header_value, expected_claims)
  local token = string.match(header_value, "Bearer (.*)")
  local jwt_obj = jwt:load_jwt(token)
  assert.is_true(jwt_obj.valid)

  for key, value in pairs(expected_claims) do
    assert.is_same(value, jwt_obj.payload[key],
      "JWT token claim '" .. key .. "' does not match expected value."
    )
  end

  local verified = jwt:verify_jwt_obj(RS256_PUB_KEY, jwt_obj)
  assert.is_true(verified.verified)
end

for _, strategy in helpers.all_strategies() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })

      -- Route 1 using client_credentials grant with client_secret_post auth
      local route1 = bp.routes:insert({
        hosts = { "client-credentials-with-client-secret-post-auth.com" },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route1.id },
        config = {
          oauth = {
            grant_type = "client_credentials",
            token_endpoint = KEYCLOAK_TOKEN_ENDPOINT,
            client_id = CLIENT_CREDENTIALS_GRANT_POST_AUTH_CLIENT_ID,
            client_secret = CLIENT_CREDENTIALS_GRANT_POST_AUTH_CLIENT_SECRET,
            scopes = { "openid", "profile" }
          },
          behavior = {
            upstream_access_token_header_name = "X-Custom-Auth"
          }
        }
      }

      -- Route 2 using client_credentials grant with client_secret_jwt auth
      local route2 = bp.routes:insert({
        hosts = { "client-credentials-with-client-secret-jwt-auth.com" },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route2.id },
        config = {
          client = {
            auth_method = "client_secret_jwt",
            client_secret_jwt_alg = "HS512"
          },
          oauth = {
            grant_type = "client_credentials",
            token_endpoint = KEYCLOAK_TOKEN_ENDPOINT,
            client_id = CLIENT_CREDENTIALS_GRANT_JWT_AUTH_CLIENT_ID,
            client_secret = CLIENT_CREDENTIALS_GRANT_JWT_AUTH_CLIENT_SECRET,
            scopes = { "openid", "profile" }
          }
        }
      }

      -- Route 3 using password grant with client_secret_post auth
      local route3 = bp.routes:insert({
        hosts = { "password-grant-with-client-secret-post-auth.com" },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route3.id },
        config = {
          oauth = {
            grant_type = "password",
            token_endpoint = KEYCLOAK_TOKEN_ENDPOINT,
            client_id = PASSWORD_GRANT_POST_AUTH_CLIENT_ID,
            client_secret = PASSWORD_GRANT_POST_AUTH_CLIENT_SECRET,
            username = PASSWORD_GRANT_USERNAME,
            password = PASSWORD_GRANT_PASSWORD,
            scopes = { "openid", "profile" }
          }
        }
      }
      -- Route 4 using password grant with client_secret_jwt auth
      local route4 = bp.routes:insert({
        hosts = { "password-grant-with-client-secret-jwt-auth.com" },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route4.id },
        config = {
          client = {
            auth_method = "client_secret_jwt",
            client_secret_jwt_alg = "HS512"
          },
          oauth = {
            grant_type = "password",
            token_endpoint = KEYCLOAK_TOKEN_ENDPOINT,
            client_id = PASSWORD_GRANT_JWT_AUTH_CLIENT_ID,
            client_secret = PASSWORD_GRANT_JWT_AUTH_CLIENT_SECRET,
            username = PASSWORD_GRANT_USERNAME,
            password = PASSWORD_GRANT_PASSWORD,
            scopes = { "openid", "profile" }
          }
        }
      }

      -- Create routes for each cache strategy to access tokens expiry behaviour
      for _, cache_strategy in ipairs(cache.constants.STRATEGIES) do
        -- For this route, keycloak is configured with a token lifespan of 5
        -- minutes
        local standard_expiry_test_route = bp.routes:insert({
          hosts = { "test-access-token-reuse-" .. cache_strategy .. "-cache.com" },
        })
        bp.plugins:insert {
          name = PLUGIN_NAME,
          route = { id = standard_expiry_test_route.id },
          config = {
            oauth = {
              grant_type = "client_credentials",
              token_endpoint = KEYCLOAK_TOKEN_ENDPOINT,
              client_id = CLIENT_CREDENTIALS_GRANT_POST_AUTH_CLIENT_ID,
              client_secret = CLIENT_CREDENTIALS_GRANT_POST_AUTH_CLIENT_SECRET,
              scopes = { "openid", "profile" }
            },
            cache = {
              strategy = cache_strategy,
              redis = {
                host = REDIS_HOST,
                port = REDIS_PORT,
                database = REDIS_DATABASE
              }
            }
          }
        }
        -- For this route, keycloak is configured with a token lifespan of 5
        -- seconds and we'll set the cache to expire it 3 seconds early.
        local short_expiry_test_route = bp.routes:insert({
          hosts = { "test-access-token-expires-" .. cache_strategy .. "-cache.com" },
        })
        bp.plugins:insert {
          name = PLUGIN_NAME,
          route = { id = short_expiry_test_route.id },
          config = {
            oauth = {
              grant_type = "client_credentials",
              token_endpoint = KEYCLOAK_TOKEN_ENDPOINT,
              client_id = ACCESS_TOKEN_EXPIRY_CLIENT_ID,
              client_secret = ACCESS_TOKEN_EXPIRY_CLIENT_SECRET,
              scopes = { "openid", "profile" }
            },
            cache = {
              eagerly_expire = 3,
              strategy = cache_strategy,
              redis = {
                host = REDIS_HOST,
                port = REDIS_PORT,
                database = REDIS_DATABASE
              }
            }
          }
        }
      end

      assert(helpers.start_kong({
        database           = strategy,
        nginx_conf         = "spec/fixtures/custom_nginx.template",
        plugins            = "bundled," .. PLUGIN_NAME,
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then client:close() end
    end)

    describe("request", function()
      it("is authenticated using client-credentials grant using client_secret_post authentication", function()
        local r = client:get("/request", {
          headers = {
            host = "client-credentials-with-client-secret-post-auth.com"
          }
        })
        assert.response(r).has.status(200)
        -- Check the echoed request's X-Custom-Auth header
        local header_value = assert.request(r).has.header("X-Custom-Auth")
        validate_authorization_header(header_value, {
          iss = KEYCLOAK_ISSUER,
          azp = CLIENT_CREDENTIALS_GRANT_POST_AUTH_CLIENT_ID
        })
      end)

      it("is authenticated using client-credentials grant using client_secret_jwt authentication", function()
        local r = client:get("/request", {
          headers = {
            host = "client-credentials-with-client-secret-jwt-auth.com"
          }
        })
        assert.response(r).has.status(200)
        -- Check the echoed request's Authorization header
        local header_value = assert.request(r).has.header("authorization")
        validate_authorization_header(header_value, {
          iss = KEYCLOAK_ISSUER,
          azp = CLIENT_CREDENTIALS_GRANT_JWT_AUTH_CLIENT_ID
        })
      end)

      it("is authenticated using resource owner password credentials grant using client_secret_post authentication",
      function()
        local r = client:get("/request", {
          headers = {
            host = "password-grant-with-client-secret-post-auth.com"
          }
        })
        assert.response(r).has.status(200)
        -- Check the echoed request's Authorization header
        local header_value = assert.request(r).has.header("authorization")
        validate_authorization_header(header_value, {
          iss = KEYCLOAK_ISSUER,
          azp = PASSWORD_GRANT_POST_AUTH_CLIENT_ID,
          preferred_username = PASSWORD_GRANT_USERNAME,
          email = PASSWORD_GRANT_EMAIL
        })
      end)

      it("is authenticated using resource owner password credentials grant using client_secret_jwt authentication",
      function()
        local r = client:get("/request", {
          headers = {
            host = "password-grant-with-client-secret-jwt-auth.com"
          }
        })
        assert.response(r).has.status(200)
        -- Check the echoed request's Authorization header
        local header_value = assert.request(r).has.header("authorization")
        validate_authorization_header(header_value, {
          iss = KEYCLOAK_ISSUER,
          azp = PASSWORD_GRANT_JWT_AUTH_CLIENT_ID,
          preferred_username = PASSWORD_GRANT_USERNAME,
          email = PASSWORD_GRANT_EMAIL
        })
      end)

      for _, cache_strategy in ipairs(cache.constants.STRATEGIES) do
        it("reuses tokens if they do not expire (" .. cache_strategy .. " cache)", function()
          -- Initial request will get a new access token and cache it
          local request1 = client:get("/request", {
            headers = {
              host = "test-access-token-reuse-" .. cache_strategy .. "-cache.com"
            }
          })
          assert.response(request1).has.status(200)
          local header_value1 = assert.request(request1).has.header("authorization")
          validate_authorization_header(header_value1, {
            iss = KEYCLOAK_ISSUER,
            azp = CLIENT_CREDENTIALS_GRANT_POST_AUTH_CLIENT_ID,
          })

          client:close()
          client = helpers.proxy_client()

          -- Second request will re-use the same access token
          local request2 = client:get("/request", {
            headers = {
              host = "test-access-token-reuse-" .. cache_strategy .. "-cache.com"
            }
          })
          assert.response(request2).has.status(200)
          local header_value2 = assert.request(request2).has.header("authorization")
          validate_authorization_header(header_value2, {
            iss = KEYCLOAK_ISSUER,
            azp = CLIENT_CREDENTIALS_GRANT_POST_AUTH_CLIENT_ID,
          })

          -- Check access tokens match
          assert.is_same(header_value1, header_value2)
        end)

        it("purges tokens as the result of an upstream authentication error (" .. cache_strategy .. " cache)",
        function()
          -- Initial request will get a new access token and cache it
          local request1 = client:get("/request", {
            headers = {
              host = "test-access-token-reuse-" .. cache_strategy .. "-cache.com"
            }
          })
          assert.response(request1).has.status(200)
          local header_value1 = assert.request(request1).has.header("authorization")
          validate_authorization_header(header_value1, {
            iss = KEYCLOAK_ISSUER,
            azp = CLIENT_CREDENTIALS_GRANT_POST_AUTH_CLIENT_ID,
          })

          client:close()
          client = helpers.proxy_client()

          -- Second request will cause the access token to be purged due to 401 response
          local request2 = client:get("/status/401", {
            headers = {
              host = "test-access-token-reuse-" .. cache_strategy .. "-cache.com"
            }
          })
          assert.response(request2).has.status(401)

          client:close()
          client = helpers.proxy_client()

          -- Third request will get a new access token and cache it again
          local request3 = client:get("/request", {
            headers = {
              host = "test-access-token-reuse-" .. cache_strategy .. "-cache.com"
            }
          })
          assert.response(request3).has.status(200)
          local header_value3 = assert.request(request3).has.header("authorization")
          validate_authorization_header(header_value3, {
            iss = KEYCLOAK_ISSUER,
            azp = CLIENT_CREDENTIALS_GRANT_POST_AUTH_CLIENT_ID,
          })

          -- The third access token should be different from the first access token
          assert.is_not_same(header_value1, header_value3)
        end)

        it("re-issues new tokens when they expire (" .. cache_strategy .. " cache)", function()
          -- Initial request will get a new access token and cache it
          local request1 = client:get("/request", {
            headers = {
              host = "test-access-token-expires-" .. cache_strategy .. "-cache.com"
            }
          })
          assert.response(request1).has.status(200)
          local header_value1 = assert.request(request1).has.header("authorization")
          validate_authorization_header(header_value1, {
            iss = KEYCLOAK_ISSUER,
            azp = ACCESS_TOKEN_EXPIRY_CLIENT_ID,
          })

          client:close()
          client = helpers.proxy_client()

          -- Sleep until the token should be expired
          ngx.sleep(2)

          -- Second request should result in new access token
          local request2 = client:get("/request", {
            headers = {
              host = "test-access-token-expires-" .. cache_strategy .. "-cache.com"
            }
          })
          assert.response(request2).has.status(200)
          local header_value2 = assert.request(request2).has.header("authorization")
          validate_authorization_header(header_value2, {
            iss = KEYCLOAK_ISSUER,
            azp = ACCESS_TOKEN_EXPIRY_CLIENT_ID,
          })

          -- Second access token should not be the same as the first one
          assert.is_not_same(header_value1, header_value2)
        end)
      end
    end)
  end)
end
