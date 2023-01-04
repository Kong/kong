-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local plugin_name = "jwt-signer"
local fmt = string.format


local bp, admin_client, proxy_client, err_log_file
for _, strategy in helpers.each_strategy() do
  describe(fmt("%s - access phase default config", plugin_name), function()
    lazy_setup(function()
      bp, _ = helpers.get_db_utils(strategy, nil, { plugin_name })
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
      err_log_file = helpers.test_conf.nginx_err_logs
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if admin_client then admin_client:close() end
      if proxy_client then proxy_client:close() end
      assert(helpers.stop_kong())
    end)

    after_each(function()
      helpers.clean_logfile(err_log_file)
    end)

    it("finds no Authorization header", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/default",
      })
      assert.response(res).has.status(401)
      assert.logfile(err_log_file).has.line("access token was not found")
    end)

    it("finds a token in the header but it is invalid", function()
      -- expect token introspection (jwt-siger thinks this is a opaque token)
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/default",
        headers = {
          ["Authorization"] = "invalidjwt",
        }
      })
      assert.response(res).has.status(500)
      assert.logfile(err_log_file).has_not.line("access token was not found")
      assert.logfile(err_log_file).has.line("access token present")
      assert.logfile(err_log_file).has_not.line("access token jws")
      assert.logfile(err_log_file).has.line("access token opaque")
      assert.logfile(err_log_file).has.line("access token could not be introspected because introspection endpoint was not specified")
    end)

    it("finds a token in the header that starts with <basic> but isn't a valid JWT", function()
      -- expect token introspection (jwt-siger thinks this is a opaque token)
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/default",
        headers = {
          ["Authorization"] = "Basic invalidjwt",
        }
      })
      assert.response(res).has.status(500)
      assert.logfile(err_log_file).has_not.line("access token was not found")
      assert.logfile(err_log_file).has_not.line("access token jws")
      assert.logfile(err_log_file).has.line("access token present")
      assert.logfile(err_log_file).has.line("access token opaque")
      assert.logfile(err_log_file).has.line("access token could not be introspected because introspection endpoint was not specified")
    end)

    it("finds a token in the header that starts with <bearer> but isn't a valid JWT", function()
      -- expect token introspection (jwt-siger thinks this is a opaque token)
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/default",
        headers = {
          ["Authorization"] = "Bearer invalidjwt",
        }
      })
      assert.response(res).has.status(500)
      assert.logfile(err_log_file).has.line("access token present")
      assert.logfile(err_log_file).has_not.line("access token jws")
      assert.logfile(err_log_file).has.line("access token opaque")
      assert.logfile(err_log_file).has.line("access token could not be introspected because introspection endpoint was not specified")
    end)

    it("finds a token in the header that starts with <bearer> and is a valid JWT", function()
      -- expect token introspection (jwt-siger thinks this is a opaque token)
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/default",
        headers = {
          ["Authorization"] = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
        }
      })
      assert.logfile(err_log_file).has_not.line("access token was not found")
      assert.logfile(err_log_file).has.line("access token jws")
      -- on a valid default configuration it tries to verify the signature
      assert.logfile(err_log_file).has.line("access token signature verification")
      -- but fails to do so when no jwks endpoint is specified
      assert.logfile(err_log_file).has.line("access token signature cannot be verified because jwks endpoint was not specified")
      assert.response(res).has.status(401)
    end)

    it("finds a token in the header that starts with <Basic> and is a valid JWT", function()
      -- expect token introspection (jwt-siger thinks this is a opaque token)
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/default",
        headers = {
          ["Authorization"] = "Basic eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
        }
      })
      assert.response(res).has.status(401)
      assert.logfile(err_log_file).has_not.line("access token was not found")
      assert.logfile(err_log_file).has.line("access token jws")
      -- on a valid default configuration it tries to verify the signature
      assert.logfile(err_log_file).has.line("access token signature verification")
      -- but fails to do so when no jwks endpoint is specified
      assert.logfile(err_log_file).has.line("access token signature cannot be verified because jwks endpoint was not specified")
    end)
  end)

  describe(fmt("%s - signature verification", plugin_name), function()
    lazy_setup(function()
      bp, _ = helpers.get_db_utils(strategy, nil, { plugin_name })
      local route = bp.routes:insert({ paths = { "/verify" }, })
      local route2 = bp.routes:insert({ paths = { "/verify-bad-url" }, })
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
      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      err_log_file = helpers.test_conf.nginx_err_logs
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if admin_client then admin_client:close() end
      if proxy_client then proxy_client:close() end
      assert(helpers.stop_kong())
    end)

    after_each(function()
      helpers.clean_logfile(err_log_file)
    end)

    it("can load keys from URL but could not sign", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/verify",
        headers = {
          ["Authorization"] = "Basic eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
        }
      })
      assert.response(res).has.status(401)
      assert.logfile(err_log_file).has_not.line("access token was not found")
      assert.logfile(err_log_file).has.line("access token present")
      assert.logfile(err_log_file).has.line("access token jws")
      assert.logfile(err_log_file).has.line("access token signature verification")
      assert.logfile(err_log_file).has.line("loading jwks from database for https://www.googleapis.com/oauth2/v3/certs")
    end)

    it("can not load keys", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/verify-bad-url",
        headers = {
          ["Authorization"] = "Basic eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
        }
      })
      assert.response(res).has.status(401)
      assert.logfile(err_log_file).has_not.line("access token was not found")
      assert.logfile(err_log_file).has.line("access token present")
      assert.logfile(err_log_file).has.line("access token jws")
      assert.logfile(err_log_file).has.line("access token signature verification")
      assert.logfile(err_log_file).has.line("loading jwks from database for https://www.no-jwks-here.org")
    end)

    pending("a testcase to verify signature of a signed access token", function()
      -- create a token with a known keypair (or secret)
      -- pass the token to the plugin.
      -- check verification
    end)
  end)


  describe(fmt("%s - access phase without verification and optional channel tokens", plugin_name), function()
    lazy_setup(function()
      bp, _ = helpers.get_db_utils(strategy, nil, { plugin_name })
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
      err_log_file = helpers.test_conf.nginx_err_logs
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if admin_client then admin_client:close() end
      if proxy_client then proxy_client:close() end
      assert(helpers.stop_kong())
    end)

    after_each(function()
      helpers.clean_logfile(err_log_file)
    end)

    it("can decode", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/no-verify-optional-channel",
        headers = {
          ["Authorization"] = "Basic eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
        }
      })
      assert.response(res).has.status(200)
      assert.logfile(err_log_file).has.line("access token expiry verification")
      assert.logfile(err_log_file).has.line("access token scopes verification")
      assert.logfile(err_log_file).has.line("access token signing")
      assert.logfile(err_log_file).has.line("loading jwks from database for kong")
      assert.logfile(err_log_file).has.line("channel token was not found")
    end)

    -- TODO: generate token with malformed payload
    pending("decodes but to a non-string value", function() end)

    it("decodes but has no payload", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/no-verify-optional-channel",
        headers = {
          -- payload is missing                                          here
          ["Authorization"] = "Basic eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..Et9HFtf9R3GEMA0IICOfFMVXY7kkTX1wr4qCyhIf58U"
        }
      })
      assert.response(res).has.status(401)
      assert.logfile(err_log_file).has.line("access token present")
      assert.logfile(err_log_file).has.line("access token jws")
      assert.logfile(err_log_file).has.line("access token could not be decoded")
      assert.logfile(err_log_file).has.line("unable to json decode jws payload")

    end)
  end)

  describe(fmt("%s - access phase - simple scope verification -", plugin_name), function()
    lazy_setup(function()
      bp, _ = helpers.get_db_utils(strategy, nil, { plugin_name })
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
      err_log_file = helpers.test_conf.nginx_err_logs
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if admin_client then admin_client:close() end
      if proxy_client then proxy_client:close() end
      assert(helpers.stop_kong())
    end)

    after_each(function()
      helpers.clean_logfile(err_log_file)
    end)

    it("passes with existing scopes", function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/scope-verification-passed",
        headers = {
          ["authorization"] = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        }
      })
      assert.response(res).has.status(200)
      assert.logfile(err_log_file).has.line("access token present")
      assert.logfile(err_log_file).has.line("access token jws")
      assert.logfile(err_log_file).has.line("access token expiry verification")
      assert.logfile(err_log_file).has.line("access token scopes verification")
      assert.logfile(err_log_file).has.line("access token signing")
      assert.logfile(err_log_file).has.line("access token upstream header")
    end)

    it("fails with non-existant scopes", function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/scope-verification-failed",
        headers = {
          ["authorization"] = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        }
      })
      assert.response(res).has.status(403)
      assert.logfile(err_log_file).has.line("access token present")
      assert.logfile(err_log_file).has.line("access token jws")
    end)
  end)

  describe(fmt("%s - expiry verification", plugin_name), function()
    lazy_setup(function()
      bp, _ = helpers.get_db_utils(strategy, nil, { plugin_name })
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
      err_log_file = helpers.test_conf.nginx_err_logs
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if admin_client then admin_client:close() end
      if proxy_client then proxy_client:close() end
      assert(helpers.stop_kong())
    end)

    after_each(function()
      helpers.clean_logfile(err_log_file)
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
      assert.logfile(err_log_file).has.line("access token present")
      assert.logfile(err_log_file).has.line("access token jws")
      assert.logfile(err_log_file).has.line("access token expiry verification")
      assert.logfile(err_log_file).has.line("access token is expired")
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
      assert.logfile(err_log_file).has.line("access token present")
      assert.logfile(err_log_file).has.line("access token jws")
      assert.logfile(err_log_file).has.line("access token expiry verification")
      assert.logfile(err_log_file).has.line("access token is expired")
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
      assert.logfile(err_log_file).has.line("access token present")
      assert.logfile(err_log_file).has.line("access token jws")
      assert.logfile(err_log_file).has.line("access token expiry verification")
      assert.logfile(err_log_file).has.line("access token is expired")
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
      assert.logfile(err_log_file).has.line("access token present")
      assert.logfile(err_log_file).has.line("access token jws")
      assert.logfile(err_log_file).has_not.line("access token expiry verification")
      assert.logfile(err_log_file).has_not.line("access token is expired")
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
      assert.logfile(err_log_file).has.line("access token present")
      assert.logfile(err_log_file).has.line("access token jws")
      assert.logfile(err_log_file).has_not.line("access token expiry verification")
      assert.logfile(err_log_file).has_not.line("access token is expired")
    end)
  end)

  describe("signing without consumer scoping", function()
    lazy_setup(function()
      bp, _ = helpers.get_db_utils(strategy, nil, { plugin_name })
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
      assert(bp.consumers:insert({
        username = "John Doe"
      }))
      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      err_log_file = helpers.test_conf.nginx_err_logs
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if admin_client then admin_client:close() end
      if proxy_client then proxy_client:close() end
      assert(helpers.stop_kong())
    end)

    after_each(function()
      helpers.clean_logfile(err_log_file)
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
      assert.logfile(err_log_file).has.line("access token present")
      assert.logfile(err_log_file).has.line("access token jws")
      assert.logfile(err_log_file).has_not.line("consumer search order was not specified")
      assert.logfile(err_log_file).has_not.line("consumer claim could not be found")
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
      assert.logfile(err_log_file).has.line("access token present")
      assert.logfile(err_log_file).has.line("access token jws")
      assert.logfile(err_log_file).has_not.line("consumer search order was not specified")
      assert.logfile(err_log_file).has.line("consumer claim could not be found")
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
        assert.logfile(err_log_file).has.line("access token present")
        assert.logfile(err_log_file).has.line("access token jws")
        assert.logfile(err_log_file).has_not.line("consumer search order was not specified")
        assert.logfile(err_log_file).has_not.line("consumer claim could not be found")
        assert.logfile(err_log_file).has.line("consumer could not be found")
      end)

    it("returns 200 because consumer_claims were configured and found and could not be mapped to a consumer",
      function()
        local res = assert(proxy_client:send {
          method = "get",
          path = "/consumer-claims-consumer-found",
          headers = {
            ["authorization"] = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
          }
        })
        assert.response(res).has.status(200)
        assert.logfile(err_log_file).has.line("access token present")
        assert.logfile(err_log_file).has.line("access token jws")
        assert.logfile(err_log_file).has_not.line("consumer claim could not be found")
        assert.logfile(err_log_file).has_not.line("consumer could not be found")
      end)
  end)
end
