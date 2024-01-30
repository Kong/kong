-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local plugin_name = "jwt-signer"
local fmt = string.format
local jwt = require "kong.enterprise_edition.jwt"
local ngx_null = ngx.null
local codec = require "kong.openid-connect.codec"
local base64url = codec.base64url


local bp, admin_client, proxy_client
for _, strategy in helpers.each_strategy({ "postgres", "off" }) do
  describe(fmt("%s - access phase default config", plugin_name), function()
    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, nil, { plugin_name })
      local route = bp.routes:insert({ paths = { "/default" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route
      }))

      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if admin_client then admin_client:close() end
      if proxy_client then proxy_client:close() end
      assert(helpers.stop_kong())
    end)

    after_each(function()
      helpers.clean_logfile()
    end)

    it("returns 401 as it finds no Authorization header", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/default",
      })
      assert.response(res).has.status(401)
      assert.logfile().has.line("access token was not found")
    end)

    it("returns 500 as it finds a token in the header but it is invalid", function()
      -- expect token introspection (jwt-siger thinks this is a opaque token)
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/default",
        headers = {
          ["Authorization"] = "invalidjwt",
        }
      })
      assert.response(res).has.status(500)
      assert.logfile().has_not.line("access token was not found")
      assert.logfile().has.line("access token present")
      assert.logfile().has_not.line("access token jws")
      assert.logfile().has.line("access token opaque")
      assert.logfile().has.line("access token could not be introspected because introspection endpoint was not specified")
    end)

    it("returns 500 as it finds a token in the header that starts with <basic> but isn't a valid JWT", function()
      -- expect token introspection (jwt-siger thinks this is a opaque token)
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/default",
        headers = {
          ["Authorization"] = "Basic invalidjwt",
        }
      })
      assert.response(res).has.status(500)
      assert.logfile().has_not.line("access token was not found")
      assert.logfile().has_not.line("access token jws")
      assert.logfile().has.line("access token present")
      assert.logfile().has.line("access token opaque")
      assert.logfile().has.line("access token could not be introspected because introspection endpoint was not specified")
    end)

    it("returns 500 as it finds a token in the header that starts with <bearer> but isn't a valid JWT", function()
      -- expect token introspection (jwt-siger thinks this is a opaque token)
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/default",
        headers = {
          ["Authorization"] = "Bearer invalidjwt",
        }
      })
      assert.response(res).has.status(500)
      assert.logfile().has.line("access token present")
      assert.logfile().has_not.line("access token jws")
      assert.logfile().has.line("access token opaque")
      assert.logfile().has.line("access token could not be introspected because introspection endpoint was not specified")
    end)

    it("returns 401 as it finds a token in the header that starts with <bearer> and is a valid JWT", function()
      -- expect token introspection (jwt-siger thinks this is a opaque token)
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/default",
        headers = {
          ["Authorization"] = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
        }
      })
      assert.response(res).has.status(401)
      assert.logfile().has_not.line("access token was not found")
      assert.logfile().has.line("access token jws")
      -- on a valid default configuration it tries to verify the signature
      assert.logfile().has.line("access token signature verification")
      -- but fails to do so when no jwks endpoint is specified
      assert.logfile().has.line("access token signature cannot be verified because jwks endpoint was not specified")
    end)

    it("returns 401 as it finds a token in the header that starts with <Basic> and is a valid JWT", function()
      -- expect token introspection (jwt-siger thinks this is a opaque token)
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/default",
        headers = {
          ["Authorization"] = "Basic eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
        }
      })
      assert.response(res).has.status(401)
      assert.logfile().has_not.line("access token was not found")
      assert.logfile().has.line("access token jws")
      -- on a valid default configuration it tries to verify the signature
      assert.logfile().has.line("access token signature verification")
      -- but fails to do so when no jwks endpoint is specified
      assert.logfile().has.line("access token signature cannot be verified because jwks endpoint was not specified")
    end)
  end)

  describe(fmt("%s - signature verification", plugin_name), function()
    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, nil, { plugin_name })
      local route = bp.routes:insert({ paths = { "/verify" }, })
      local route2 = bp.routes:insert({ paths = { "/verify-bad-url" }, })
      local route3 = bp.routes:insert({ paths = { "/sign" }, })
      local route4 = bp.routes:insert({ paths = { "/verify-known-token" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route,
        config = {
          -- default is true, just for explicity
          verify_access_token_signature = true,
          access_token_jwks_uri = "https://www.googleapis.com/oauth2/v3/certs"
        }
      }))
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route2,
        config = {
          -- default is true, just for explicity
          verify_access_token_signature = true,
          access_token_jwks_uri = "https://www.no-jwks-here.org"
        }
      }))
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route3,
        config = {
          -- default is true, just for explicity
          channel_token_optional = true,
          verify_access_token_signature = false,
          access_token_signing_algorithm = "ES256",
          access_token_upstream_header = "Authorization",
          access_token_keyset = "kong"
        }
      }))
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route4,
        config = {
          -- default is true, just for explicity
          channel_token_optional = true,
          verify_access_token_signature = false,
          access_token_signing_algorithm = "ES256",
          access_token_upstream_header = "Authorization",
          access_token_keyset = "http://localhost:9543/ec-keys"
        }
      }))


      local jwks_fixture = {
        http_mock = {
          mock_introspection = [[
            server {
              server_name jwks_mock;
              listen 0.0.0.0:9543;
              location = /ec-keys {
                content_by_lua_block {
                  ngx.header.content_type = "application/jwk-set+json"
                  ngx.say('{"keys":[{"kty":"EC","crv":"P-256","y":"kGe5DgSIycKp8w9aJmoHhB1sB3QTugfnRWm5nU_TzsY","alg":"ES256","kid":"19J8y7Zprt2-QKLjF2I5pVk0OELX6cY2AfaAv1LC_w8","x":"EVs_o5-uQbTjL3chynL4wXgUg2R9q9UU8I5mEovUf84","d":"evZzL1gdAFr88hb2OF_2NxApJCzGCEDdfSp6VQO30hw"}]}')
                }
              }
            }
          ]]
        }
      }

      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
        database   = strategy,
        plugins    = plugin_name,
      }, nil, nil, jwks_fixture))
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if admin_client then admin_client:close() end
      if proxy_client then proxy_client:close() end
      assert(helpers.stop_kong())
    end)

    after_each(function()
      helpers.clean_logfile()
    end)

    it("returns 401 as it can load keys from URL but could not sign", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/verify",
        headers = {
          ["Authorization"] = "Basic eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
        }
      })
      assert.response(res).has.status(401)
      assert.logfile().has_not.line("access token was not found")
      assert.logfile().has.line("access token present")
      assert.logfile().has.line("access token jws")
      assert.logfile().has.line("access token signature verification")
      assert.logfile().has.line("loading jwks from database for https://www.googleapis.com/oauth2/v3/certs")
    end)

    it("returns 401 as it can not load keys", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/verify-bad-url",
        headers = {
          ["Authorization"] = "Basic eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
        }
      })
      assert.response(res).has.status(401)
      assert.logfile().has_not.line("access token was not found")
      assert.logfile().has.line("access token present")
      assert.logfile().has.line("access token jws")
      assert.logfile().has.line("access token signature verification")
      assert.logfile().has.line("loading jwks from database for https://www.no-jwks-here.org")
    end)

    it("re-sign a token with a ES256 key and expect a raw(r..s) formatted signature", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/sign",
        headers = {
          ["Authorization"] = "Basic eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
        }
      })
      assert.logfile().has_not.line("access token was not found")
      assert.logfile().has.line("access token present")
      assert.logfile().has.line("access token jws")
      assert.logfile().has.line("access token signing")
      assert.logfile().has.line("access token upstream header")
      assert.response(res).has.status(200)
      local header = assert.request(res).has.header("Authorization")
      local sig = string.match(header, "[^%.]+$")
      -- The JWS Signature value MUST be a 64-octet sequence.
      assert(#base64url.decode(sig), 64)
    end)

    it("receives token with verifyable signature #XX", function ()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/verify-known-token",
        headers = {
          -- A valid, signed token created with keys that are loaded into this plugin
          -- (see fixtures/jwks/keys.conf)
          ["Authorization"] = "Bearer eyJhbGciOiJFUzI1NiIsImFhYSI6dHJ1ZX0.eyJ0ZXN0IjoicnVuIn0.pabNEK6k3SxDV0jGe3Qs0WCGmqu6tPI-rj2FASCnDRWFEMM1Viy3kn14Gp2g45RnoFXnN0SKiHMr4-OQVuSoCg",
        }
      })
      assert.logfile().has_not.line("access token was not found")
      assert.logfile().has.line("access token present")
      assert.logfile().has.line("access token jws")
      assert.logfile().has.line("access token signing")
      assert.logfile().has.line("access token upstream header")
      assert.response(res).has.status(200)
    end)
  end)


  describe(fmt("%s - access phase without verification and optional channel tokens", plugin_name), function()
    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, nil, { plugin_name })
      local route = bp.routes:insert({ paths = { "/no-verify-optional-channel" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route,
        config = {
          verify_access_token_signature = false,
          channel_token_optional = true
        }
      }))
      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if admin_client then admin_client:close() end
      if proxy_client then proxy_client:close() end
      assert(helpers.stop_kong())
    end)

    after_each(function()
      helpers.clean_logfile()
    end)

    it("returns 200 as it can decode the payload", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/no-verify-optional-channel",
        headers = {
          ["Authorization"] = "Basic eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
        }
      })
      assert.response(res).has.status(200)
      assert.logfile().has.line("access token expiry verification")
      assert.logfile().has.line("access token scopes verification")
      assert.logfile().has.line("access token signing")
      assert.logfile().has.line("loading jwks from database for kong")
      assert.logfile().has.line("channel token was not found")
    end)

    -- TODO: generate token with malformed payload
    pending("decodes but to a non-string value", function() end)

    it("returns 401 as it decodes correctly but has no payload", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/no-verify-optional-channel",
        headers = {
          -- payload is missing                                          here
          ["Authorization"] = "Basic eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..Et9HFtf9R3GEMA0IICOfFMVXY7kkTX1wr4qCyhIf58U"
        }
      })
      assert.response(res).has.status(401)
      assert.logfile().has.line("access token present")
      assert.logfile().has.line("access token jws")
      assert.logfile().has.line("access token could not be decoded")
      assert.logfile().has.line("unable to json decode jws payload")

    end)
  end)

  describe(fmt("%s - access phase - simple scope verification -", plugin_name), function()
    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, nil, { plugin_name })
      local route = bp.routes:insert({ paths = { "/scope-verification-failed" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route,
        config = {
          -- to just test signing
          verify_access_token_signature = false,
          channel_token_optional = true,
          verify_access_token_scopes = true,
          access_token_scopes_claim = {
            "name"
          },
          access_token_scopes_required = {
            "some other dude"
          }
        }
      }))
      local route2 = bp.routes:insert({ paths = { "/scope-verification-passed" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route2,
        config = {
          -- to just test signing
          verify_access_token_signature = false,
          channel_token_optional = true,
          access_token_scopes_claim = {
            "name"
          },
          verify_access_token_scopes = true,
          access_token_scopes_required = {
            "John Doe",
          }
        }
      }))
      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if admin_client then admin_client:close() end
      if proxy_client then proxy_client:close() end
      assert(helpers.stop_kong())
    end)

    after_each(function()
      helpers.clean_logfile()
    end)

    it("returns 200 as it passes with existing scopes", function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/scope-verification-passed",
        headers = {
          ["authorization"] = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        }
      })
      assert.response(res).has.status(200)
      assert.logfile().has.line("access token present")
      assert.logfile().has.line("access token jws")
      assert.logfile().has.line("access token expiry verification")
      assert.logfile().has.line("access token scopes verification")
      assert.logfile().has.line("access token signing")
      assert.logfile().has.line("access token upstream header")
    end)

    it("returns 403 as it fails with non-existant scopes", function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/scope-verification-failed",
        headers = {
          ["authorization"] = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        }
      })
      assert.response(res).has.status(403)
      assert.logfile().has.line("access token present")
      assert.logfile().has.line("access token jws")
    end)
  end)

  describe(fmt("%s - expiry verification", plugin_name), function()
    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, nil, { plugin_name })
      local route = bp.routes:insert({ paths = { "/expired" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route,
        config = {
          -- to just test signing
          verify_access_token_signature = false,
          channel_token_optional = true,
          verify_access_token_expiry = true,
        }
      }))
      local route2 = bp.routes:insert({ paths = { "/expired-but-no-expiry-configured" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route2,
        config = {
          -- to just test signing
          verify_access_token_signature = false,
          channel_token_optional = true,
          verify_access_token_expiry = false,
        }
      }))
      local route3 = bp.routes:insert({ paths = { "/expired-leeway" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route3,
        config = {
          -- to just test signing
          verify_access_token_signature = false,
          channel_token_optional = true,
          verify_access_token_expiry = true,
          -- force any expired token to be valid
          access_token_leeway = 99999999999
        }
      }))
      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if admin_client then admin_client:close() end
      if proxy_client then proxy_client:close() end
      assert(helpers.stop_kong())
    end)

    after_each(function()
      helpers.clean_logfile()
    end)

    it("returns 401 becuase the JWT is expired", function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/expired",
        headers = {
          -- exp: 1970
          ["authorization"] = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJleHAiOjEwMDAwMDB9.wnzTGZauW_Af9RUi1vPRvkRF_jYKqfjjgdTWVZQOT-w"
        }
      })
      assert.response(res).has.status(401)
      assert.logfile().has.line("access token present")
      assert.logfile().has.line("access token jws")
      assert.logfile().has.line("access token expiry verification")
      assert.logfile().has.line("access token is expired")
    end)

    it("returns 401 becuase the JWT has exp: 0", function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/expired",
        headers = {
          -- exp: 0
          ["authorization"] = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJleHAiOjB9.JWKPB-5Q8rTYzl-MfhRGpP9WpDpQxC7JkIAGFMDZnpg"
        }
      })
      assert.response(res).has.status(401)
      assert.logfile().has.line("access token present")
      assert.logfile().has.line("access token jws")
      assert.logfile().has.line("access token expiry verification")
      assert.logfile().has.line("access token is expired")
    end)

    it("returns 401 becuase the JWT has negative exp value", function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/expired",
        headers = {
          -- exp: -9999999999
          ["authorization"] = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJleHAiOi05OTk5OTk5OTk5OX0.42UvHeMqhxwbAy5Hva3jvQzD7mGNilmHc2aLa0qjWzk"
        }
      })
      assert.response(res).has.status(401)
      assert.logfile().has.line("access token present")
      assert.logfile().has.line("access token jws")
      assert.logfile().has.line("access token expiry verification")
      assert.logfile().has.line("access token is expired")
    end)

    it("returns 200 although JWT has is expired but the plugin is configured with `verify_expiry=false`", function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/expired-but-no-expiry-configured",
        headers = {
          -- exp: 1970
          ["authorization"] = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJleHAiOjEwMDAwMDB9.wnzTGZauW_Af9RUi1vPRvkRF_jYKqfjjgdTWVZQOT-w"
        }
      })
      assert.response(res).has.status(200)
      assert.logfile().has.line("access token present")
      assert.logfile().has.line("access token jws")
      assert.logfile().has_not.line("access token expiry verification")
      assert.logfile().has_not.line("access token is expired")
    end)

    it("returns 200 although JWT has is expired but the plugin is configured with leeway 9999999999999", function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/expired-but-no-expiry-configured",
        headers = {
          -- exp: 21 Dec 2022
          ["authorization"] = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJleHAiOjE2NzE2MzI4NjJ9.BGPkZN3W0y2tSe9GSCO95n7wMyQtLe3iZh8iCgCmTlI"
        }
      })
      assert.response(res).has.status(200)
      assert.logfile().has.line("access token present")
      assert.logfile().has.line("access token jws")
      assert.logfile().has_not.line("access token expiry verification")
      assert.logfile().has_not.line("access token is expired")
    end)
  end)

  describe(fmt("%s - signing consumers with consumer mapping", plugin_name), function()
    local consumer
    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, nil, { plugin_name , "ctx-checker-last" })
      local route = bp.routes:insert({ paths = { "/no-consumer-no-consumer-claim" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route,
        config = {
          -- to just test signing
          verify_access_token_signature = false,
          channel_token_optional = true,
          -- no claims configured
          access_token_consumer_claim = {}
        }
      }))
      local route2 = bp.routes:insert({ paths = { "/no-consumer-consumer-claims" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route2,
        config = {
          -- to just test signing
          verify_access_token_signature = false,
          channel_token_optional = true,
          access_token_consumer_claim = {
            "foo"
          }
        }
      }))
      local route3 = bp.routes:insert({ paths = { "/consumer-claims-no-consumer" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route3,
        config = {
          -- to just test signing
          verify_access_token_signature = false,
          channel_token_optional = true,
          access_token_consumer_claim = {
            -- no valid consumer under this claim
            "iat"
          }
        }
      }))
      local route4 = bp.routes:insert({ paths = { "/consumer-claims-consumer-found" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route4,
        config = {
          -- to just test signing
          verify_access_token_signature = false,
          channel_token_optional = true,
          access_token_consumer_claim = {
            -- John Doe exists
            "name"
          }
        }
      }))
      consumer = assert(bp.consumers:insert({
        username = "John Doe"
      }))

      assert(bp.plugins:insert({
        name     = "ctx-checker-last",
        route = { id = route4.id },
        config   = {
          ctx_check_field = "authenticated_consumer",
        }
      }))

      assert(helpers.start_kong({
        database   = strategy,
        plugins    = "bundled, ctx-checker-last, " .. plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if admin_client then admin_client:close() end
      if proxy_client then proxy_client:close() end
      assert(helpers.stop_kong())
    end)

    after_each(function()
      helpers.clean_logfile()
    end)

    it("returns 200 because no consumer_claim configured ", function()
      helpers.clean_logfile()
    end)

    it("returns 200 because no consumer_claim configured ", function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/no-consumer-no-consumer-claim",
        headers = {
          ["authorization"] = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        }
      })
      assert.response(res).has.status(200)
      assert.logfile().has.line("access token present")
      assert.logfile().has.line("access token jws")
      assert.logfile().has_not.line("consumer search order was not specified")
      assert.logfile().has_not.line("consumer claim could not be found")
    end)

    it("returns 403 because consumer_claims were configured but not found in the JWT", function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/no-consumer-consumer-claims",
        headers = {
          ["authorization"] = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        }
      })
      assert.response(res).has.status(403)
      assert.logfile().has.line("access token present")
      assert.logfile().has.line("access token jws")
      assert.logfile().has_not.line("consumer search order was not specified")
      assert.logfile().has.line("consumer claim could not be found")
    end)

    it("returns 403 because consumer_claims were configured and found but could not be mapped to a consumer",
      function()
        local res = assert(proxy_client:send {
          method = "get",
          path = "/consumer-claims-no-consumer",
          headers = {
            ["authorization"] = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
          }
        })
        assert.response(res).has.status(403)
        assert.logfile().has.line("access token present")
        assert.logfile().has.line("access token jws")
        assert.logfile().has_not.line("consumer search order was not specified")
        assert.logfile().has_not.line("consumer claim could not be found")
        assert.logfile().has.line("consumer could not be found")
      end)

    it("returns 200 because consumer_claims were configured and found and could be mapped to a consumer", function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/consumer-claims-consumer-found",
        headers = {
          ["authorization"] = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        }
      })
      assert.response(res).has.status(200)
      local username = assert.request(res).has.header("X-Consumer-Username")
      local id = assert.request(res).has.header("X-Consumer-ID")
      assert.equal(username, consumer.username)
      assert.equal(id, consumer.id)
      assert.request(res).has_not.header("X-Anonymous-Consumer")
      assert.logfile().has.line("access token present")
      assert.logfile().has.line("access token jws")
      assert.logfile().has_not.line("consumer claim could not be found")
      assert.logfile().has_not.line("consumer could not be found")
    end)
    it("check ctx when returns auth success", function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/consumer-claims-consumer-found",
        headers = {
          ["authorization"] = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        }
      })
      assert.response(res).has.status(200)
      local username = assert.request(res).has.header("X-Consumer-Username")
      local id = assert.request(res).has.header("X-Consumer-ID")
      assert.equal(username, consumer.username)
      assert.equal(id, consumer.id)
      assert.request(res).has_not.header("X-Anonymous-Consumer")
      assert.logfile().has.line("access token present")
      assert.logfile().has.line("access token jws")
      assert.logfile().has_not.line("consumer claim could not be found")
      assert.logfile().has_not.line("consumer could not be found")
      assert.not_nil(res.headers["ctx-checker-last-authenticated-consumer"])
      assert.matches(consumer.username, res.headers["ctx-checker-last-authenticated-consumer"])
    end)
  end)

  describe(fmt("%s config option <upstream_header>", plugin_name), function()
    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, nil, { plugin_name })
      local route = bp.routes:insert({ paths = { "/custom-upstream-header" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route,
        config = {
          -- to just test signing
          verify_access_token_signature = false,
          channel_token_optional = true,
          access_token_upstream_header = "custom-upstream-header"
        }
      }))
      local route2 = bp.routes:insert({ paths = { "/default-upstream-header" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route2,
        config = {
          -- to just test signing
          verify_access_token_signature = false,
          channel_token_optional = true,
          -- using the default value of access_token_upstream_header
        }
      }))
      local route3 = bp.routes:insert({ paths = { "/no-upstream-header" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route3,
        config = {
          -- to just test signing
          verify_access_token_signature = false,
          channel_token_optional = true,
          access_token_upstream_header = ngx_null
        }
      }))
      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if admin_client then admin_client:close() end
      if proxy_client then proxy_client:close() end
      assert(helpers.stop_kong())
    end)

    after_each(function()
      helpers.clean_logfile()
    end)

    it("returns 200 as it receives a correct custom-header with a signed JWT", function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/custom-upstream-header",
        headers = {
          ["authorization"] = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
        }
      })
      assert.response(res).has.status(200)
      local header = assert.request(res).has.header("custom-upstream-header")
      local decoded_jwt = jwt.parse_JWT(header)
      assert.is_table(decoded_jwt)
      assert.logfile().has.line("access token present")
      assert.logfile().has.line("access token jws")
      assert.logfile().has.line("access token signing")
      assert.logfile().has.line("access token upstream header")
    end)

    it("returns 200 as it receives a default header <Authorization> with a signed JWT", function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/default-upstream-header",
        headers = {
          ["authorization"] = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
        }
      })
      assert.response(res).has.status(200)
      assert.request(res).has.header("Authorization")
      assert.logfile().has.line("access token present")
      assert.logfile().has.line("access token jws")
      assert.logfile().has.line("access token signing")
      assert.logfile().has.line("access token upstream header")
    end)

    it("returns 200 and do not sign a token or set an upstream header", function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/no-upstream-header",
        headers = {
          ["authorization"] = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
        }
      })
      assert.response(res).has.status(200)
      assert.request(res).has_not.header("Authorization")
      assert.logfile().has.line("access token present")
      assert.logfile().has.line("access token jws")
      assert.logfile().has_not.line("access token signing")
      assert.logfile().has_not.line("access token upstream header")
    end)
  end)

  describe(fmt("%s valid nested scope verification", plugin_name), function()
    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, nil, { plugin_name })
      local route0 = bp.routes:insert({ paths = { "/multiple-scope-verification-passed" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route0,
        config = {
          -- to just test signing
          verify_access_token_signature = false,
          channel_token_optional = true,
          access_token_scopes_claim = {
            -- profile is the top level scope
            "profile",
            -- id is nested in profile
            "id"
          },
          verify_access_token_scopes = true,
          access_token_scopes_required = {
            -- testid is the value of the last specified scope (see access_token_scopes_claim)
            "testid"
          }
        }
      }))
      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if admin_client then admin_client:close() end
      if proxy_client then proxy_client:close() end
      assert(helpers.stop_kong())
    end)

    after_each(function()
      helpers.clean_logfile()
    end)

    it("returns 200 as it finds the defined scopes", function()
      --[[

      The token's payload looks like this
      {
        "sub": "1234567890",
        "name": "John Doe",
        "profile": {
          "id": "testid"
        },
        "iat": 1516239022
      }
      -- ]]
      local res = assert(proxy_client:send {
        method = "get",
        path = "/multiple-scope-verification-passed",
        headers = {
          ["authorization"] = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwicHJvZmlsZSI6eyJpZCI6InRlc3RpZCJ9LCJpYXQiOjE1MTYyMzkwMjJ9.hIa02JIRlIkPeEUirx2VN_1dQ1FpwGNqn_og5AwThHQ"
        }
      })
      assert.response(res).has.status(200)
      assert.logfile().has.line("access token present")
      assert.logfile().has.line("access token jws")
      assert.logfile().has.line("access token expiry verification")
      assert.logfile().has.line("access token scopes verification")
      assert.logfile().has.line("access token signing")
      assert.logfile().has.line("access token upstream header")
    end)
  end)


  describe(fmt("%s invalid nested scope verification", plugin_name), function()
    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, nil, { plugin_name })
      local route = bp.routes:insert({ paths = { "/multiple-scope-partially-exists" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route,
        config = {
          -- to just test signing
          verify_access_token_signature = false,
          channel_token_optional = true,
          verify_access_token_scopes = true,
          access_token_scopes_claim = {
            "non-existant"
          },
          access_token_scopes_required = {
            "test",
          }
        }
      }))
      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if admin_client then admin_client:close() end
      if proxy_client then proxy_client:close() end
      assert(helpers.stop_kong())
    end)

    after_each(function()
      helpers.clean_logfile()
    end)

    it("returns 403 as it fails to find the required scopes", function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/multiple-scope-partially-exists",
        headers = {
          ["authorization"] = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwicHJvZmlsZSI6eyJpZCI6InRlc3RpZCJ9LCJpYXQiOjE1MTYyMzkwMjJ9.hIa02JIRlIkPeEUirx2VN_1dQ1FpwGNqn_og5AwThHQ"
        }
      })
      assert.response(res).has.status(403)
      assert.logfile().has.line("access token present")
      assert.logfile().has.line("access token jws")
      assert.logfile().has.line("access token has no scopes while scopes were required")
      assert.logfile().has_not.line("access token signing")
      assert.logfile().has_not.line("access token upstream header")
    end)
  end)

  describe(fmt("%s - access phase without signature verification", plugin_name), function()
    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, nil, { plugin_name })
      local route = bp.routes:insert({ paths = { "/no-verify" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route,
        config = {
          verify_access_token_signature = false,
        }
      }))
      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if admin_client then admin_client:close() end
      if proxy_client then proxy_client:close() end
      assert(helpers.stop_kong())
    end)

    after_each(function()
      helpers.clean_logfile()
    end)

    it("returns 500 as no channel token provided and no explicit configuration was provided", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/no-verify",
        headers = {
          ["Authorization"] = "Basic eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
        }
      })
      -- FIXME: I would've expected that this to not raise an error
      -- but instead we get a 500
      --  channel token cannot be found because the name of the header was not specified
      -- This is the result of
      -- *channel_token_request_header not being set
      -- *channel_token_optional not being set
      -- I would assume that the defaults would suffice for the plugin to disregard channel tokens
      -- According to the docs:
      -- " By default, the plugin doesn’t look for the channel token."
      assert.response(res).has.status(500)
      assert.logfile().has.line("access token expiry verification")
      assert.logfile().has.line("access token scopes verification")
      assert.logfile().has.line("access token signing")
      assert.logfile().has.line("loading jwks from database for kong")
      assert.logfile().has.line("channel token cannot be found because the name of the header was not specified")
    end)
  end)
end
