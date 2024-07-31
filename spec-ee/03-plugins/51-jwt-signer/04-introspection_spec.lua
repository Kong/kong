-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local helpers_ee = require "spec-ee.helpers"
local plugin_name = "jwt-signer"
local jws = require "kong.openid-connect.jws"

local fmt = string.format

local introspection_fixture, introspection_url = helpers_ee.setup_oauth_introspection_fixture()


local bp, admin_client, proxy_client, plugin_instance
for _, strategy in helpers.each_strategy({ "postgres", "off" }) do
  describe(fmt("%s - introspection", plugin_name), function()
    -- Sending opaque tokens require introspection. This test involves a fixture to return static
    -- results for introspection.
    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, nil, { plugin_name })
      local route = bp.routes:insert({ paths = { "/introspection" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route,
        config = {
          -- to just test signing
          verify_access_token_signature = false,
          channel_token_optional = true,
          -- true is the default, but setting explicitly for clarity
          enable_access_token_introspection = true,
          access_token_introspection_endpoint = introspection_url,
        }
      }))
      local route2 = bp.routes:insert({ paths = { "/introspection-leeway" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route2,
        config = {
          -- to just test signing
          verify_access_token_signature = false,
          channel_token_optional = true,
          -- true is the default, but setting explicitly for clarity
          enable_access_token_introspection = true,
          access_token_introspection_endpoint = introspection_url,
          access_token_introspection_leeway = 9999999999,
        }
      }))

      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, introspection_fixture))
      --  = helpers.test_conf.nginx_err_logs
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

    pending("fails unexpectedly when no introspection endpoint is provided", function() end)

    it("grants access when valid information is retrieved for opaque token ", function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/introspection",
        headers = {
          ["authorization"] = "valid_complex"
        }
      })
      assert.response(res).has.status(200)
      assert.logfile().has.line("access token opaque")
      assert.logfile().has.line("introspecting token with http://127.0.0.1:10000/introspect")
      assert.logfile().has.line("access token introspected")
      assert.logfile().has.line("access token introspection expiry verification")
      assert.logfile().has.line("access token introspection scopes verification")
      assert.logfile().has.line("access token skipping expiry and scopes checks as introspection is trusted")
      assert.logfile().has.line("access token signing")
    end)

    it("returns 401 when introspected token is active but has no expiry field", function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/introspection",
        headers = {
          ["authorization"] = "valid"
        }
      })
      assert.response(res).has.status(401)
      assert.logfile().has.line("access token opaque")
      assert.logfile().has.line("introspecting token with http://127.0.0.1:10000/introspect")
      assert.logfile().has.line("access token introspected")
      assert.logfile().has.line("access token introspection expiry verification")
      assert.logfile().has.line("access token introspection expiry is mandatory")
      assert.logfile().has_not.line("access token signing")
    end)

    it("returns 401 when introspected token is active but expired", function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/introspection",
        headers = {
          ["authorization"] = "valid_expired"
        }
      })
      assert.response(res).has.status(401)
      assert.logfile().has.line("access token opaque")
      assert.logfile().has.line("introspecting token with http://127.0.0.1:10000/introspect")
      assert.logfile().has.line("access token introspected")
      assert.logfile().has.line("access token introspection expiry verification")
      assert.logfile().has_not.line("access token signing")
    end)

    it("returns 200 when introspected token is active but expired. leeway is configured to make the request not expired"
      , function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/introspection-leeway",
        headers = {
          ["authorization"] = "valid_expired"
        }
      })
      assert.response(res).has.status(200)
      assert.logfile().has.line("access token opaque")
      assert.logfile().has.line("introspecting token with http://127.0.0.1:10000/introspect")
      assert.logfile().has.line("access token introspected")
      assert.logfile().has.line("access token introspection expiry verification")
      assert.logfile().has.line("access token signing")
    end)



    it("returns 401 when token is not active - no error message provided with the token info", function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/introspection",
        headers = {
          ["authorization"] = "invalid_without_errors"
        }
      })
      assert.response(res).has.status(401)
      assert.logfile().has.line("access token opaque")
      assert.logfile().has.line("introspecting token with http://127.0.0.1:10000/introspect")
      assert.logfile().has.line("access token introspected")
      assert.logfile().has.line("access token inactive")
      assert.logfile().has_not.line("access token signing")
    end)

    it("returns 401 when token is not active - token.error and token.description provided in the token info",
      function()
        local res = assert(proxy_client:send {
          method = "get",
          path = "/introspection",
          headers = {
            ["authorization"] = "invalid_with_errors"
          }
        })
        assert.response(res).has.status(401)
        assert.logfile().has.line("access token opaque")
        assert.logfile().has.line("introspecting token with http://127.0.0.1:10000/introspect")
        assert.logfile().has.line("access token introspected")
        assert.logfile().has.line("dummy error: dummy error desc")
        assert.logfile().has_not.line("access token signing")
      end)
  end)

  describe(fmt("%s - introspection - claims/scopes", plugin_name), function()
    -- Sending opaque tokens require introspection. This test involves a fixture to return static
    -- results for introspection.

    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, nil, { plugin_name })
      local route0 = bp.routes:insert({ paths = { "/introspection-jwt-claim" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route0,
        config = {
          -- to just test signing
          verify_access_token_signature = false,
          channel_token_optional = true,
          -- true is the default, but setting explicitly for clarity
          enable_access_token_introspection = true,
          access_token_introspection_endpoint = introspection_url,
          access_token_introspection_jwt_claim = { "nope" }
        }
      }))

      local route1 = bp.routes:insert({ paths = { "/introspection-jwt-claim-found" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route1,
        config = {
          -- to just test signing
          verify_access_token_signature = false,
          channel_token_optional = true,
          -- true is the default, but setting explicitly for clarity
          enable_access_token_introspection = true,
          access_token_introspection_endpoint = introspection_url,
          -- looks for a key "jwt" and expects a JWT
          access_token_introspection_jwt_claim = { "jwt", "foo" }
        }
      }))

      local route2 = bp.routes:insert({ paths = { "/introspection-jwt-scopes-required" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route2,
        config = {
          -- to just test signing
          verify_access_token_signature = false,
          channel_token_optional = true,
          -- true is the default, but setting explicitly for clarity
          enable_access_token_introspection = true,
          access_token_introspection_endpoint = introspection_url,
          access_token_introspection_scopes_required = { "some_scope" },
          access_token_introspection_scopes_claim = { "scope" },
          verify_access_token_introspection_scopes = true
        }
      }))

      local route3 = bp.routes:insert({ paths = { "/introspection-jwt-scopes-required-403" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route3,
        config = {
          -- to just test signing
          verify_access_token_signature = false,
          channel_token_optional = true,
          -- true is the default, but setting explicitly for clarity
          enable_access_token_introspection = true,
          access_token_introspection_endpoint = introspection_url,
          access_token_introspection_scopes_required = { "some_scope" },
          access_token_introspection_scopes_claim = { "NOTPRESENT" },
          verify_access_token_introspection_scopes = true
        }
      }))
      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, introspection_fixture))
      --  = helpers.test_conf.nginx_err_logs
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

    it("returns 401 when introspection_jwt_claim is configured but not found", function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/introspection-jwt-claim",
        headers = {
          ["authorization"] = "valid_complex"
        }
      })
      assert.response(res).has.status(401)
      assert.logfile().has.line("access token opaque")
      assert.logfile().has.line("introspecting token with http://127.0.0.1:10000/introspect")
      assert.logfile().has.line("access token introspected")
      assert.logfile().has.line("access token introspection expiry verification")
      assert.logfile().has.line("access token could not be found in introspection jwt claim")
      assert.logfile().has_not.line("access token signing")
    end)

    it("returns 200 when verify_introspection_scopes is configured - introspection_scopes_required are present",
      function()
        local res = assert(proxy_client:send {
          method = "get",
          path = "/introspection-jwt-scopes-required",
          headers = {
            ["authorization"] = "valid_complex"
          }
        })
        assert.response(res).has.status(200)
        assert.logfile().has.line("access token opaque")
        -- assert.logfile().has.line("introspecting token with http://127.0.0.1:10000/introspect")
        assert.logfile().has.line("access token introspected")
        assert.logfile().has.line("access token introspection expiry verification")
        assert.logfile().has_not.line("access token could not be found in introspection jwt claim")
        assert.logfile().has.line("access token signing")
      end)

    it("returns 403 when verify_introspection_scopes is configured - introspection_scopes_required are present",
      function()
        local res = assert(proxy_client:send {
          method = "get",
          path = "/introspection-jwt-scopes-required-403",
          headers = {
            ["authorization"] = "valid_complex"
          }
        })
        assert.response(res).has.status(403)
        assert.logfile().has.line("access token opaque")
        assert.logfile().has.line("access token introspected")
        assert.logfile().has.line("access token introspection expiry verification")
        assert.logfile().has.line("access token has no introspection scopes while scopes were required")
        assert.logfile().has_not.line("access token signing")
      end)
  end)

  describe(fmt("%s - introspection - adding, setting and removing claims", plugin_name), function()

    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, nil, { plugin_name })
      local route = bp.routes:insert({ paths = { "/add_claims" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route,
        config = {
          -- to just test signing
          verify_access_token_signature = false,
          channel_token_optional = true,
          -- true is the default, but setting explicitly for clarity
          enable_access_token_introspection = true,
          access_token_introspection_endpoint = introspection_url,
          access_token_introspection_scopes_required = { "some_scope" },
          access_token_introspection_scopes_claim = { "scope" },
          verify_access_token_introspection_scopes = true,
          add_claims = {
            foo = "bar2",
            test = "test",
            arr1 = "{\"val1\", \"val2\"}",
          },
          set_claims = {
            bar = "qux",
            arr2 = "{\"val1\", \"val2\"}",
          },
          add_access_token_claims = {
            foo = "bar1",
            arr1 = "{\"val0\", \"val1\"}",
          },
          set_access_token_claims = {
            bar = "xuq",
          },
          remove_access_token_claims = {"username", "foo"},
        }
      }))

      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, introspection_fixture))
      --  = helpers.test_conf.nginx_err_logs
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if proxy_client then proxy_client:close() end
      assert(helpers.stop_kong())
    end)

    after_each(function()
      helpers.clean_logfile()
    end)

    it("it works",
      function()
        local res = assert(proxy_client:send {
          method = "get",
          path = "/add_claims",
          headers = {
            ["authorization"] = "valid_complex"
          }
        })
        assert.response(res).has.status(200)

        local json_table = assert.response(res).has.jsonbody()

        local auth = assert(assert(json_table.headers).authorization)
        local jwt = auth:match("^.* (.*)$")
        local decoded = assert(jws.decode(jwt, { verify_signature = false }))
        assert.same({
          client_id = "some_client_id",
          iss = "kong",
          exp = "99999999999",
          bar = "xuq",
          iat = "some_iat",
          aud = "some_aud",
          test = "test",
          scope = "some_scope",
          original_iss = "some_iss",
          sub = "some_sub",
          foo = "bar1",
          baz = "baaz",
          arr1 = "{\"val0\", \"val1\"}",
          arr2 = "{\"val1\", \"val2\"}",
        }, decoded.payload)
      end)
  end)

  describe(fmt("%s - introspection - original JWT upstream header", plugin_name), function()

    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, nil, { plugin_name })
      local route = bp.routes:insert({ paths = { "/add_claims" }, })
      plugin_instance = assert(bp.plugins:insert({
        name = plugin_name,
        route = route,
        config = {
          verify_access_token_signature = false,
          channel_token_optional = true,
          original_access_token_upstream_header = "Origin-Authorization",
          -- true is the default, but setting explicitly for clarity
          enable_access_token_introspection = true,
          access_token_introspection_endpoint = introspection_url,
        }
      }))

      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, introspection_fixture))
      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if admin_client then admin_client:close() end
      if proxy_client then proxy_client:close() end
      assert(helpers.stop_kong())
    end)

    after_each(function()
      helpers.clean_logfile()
    end)

    it("ensure the access token matches the original JWT in the specified header",
      function()
        local acc_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." ..
                          "eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ." ..
                          "GciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
        local res = assert(proxy_client:send {
          method = "get",
          path = "/add_claims",
          headers = {
            ["authorization"] = "Bearer " .. acc_token
          }
        })
        assert.response(res).has.status(200)

        local json_table = assert.response(res).has.jsonbody()

        local oauth = assert(assert(json_table.headers)["origin-authorization"])

        assert.same(acc_token, oauth)
      end)

    it("should fail when original_channel_token_upstream_header is the same to the access token's",
      function()
        local res = assert(admin_client:send {
          method = "patch",
          path = "/plugins/" .. plugin_instance.id,
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded"
          },
          body = "config.original_channel_token_upstream_header=Origin-Authorization",
        })
        assert.response(res).has.status(400)
        local json_table = assert.response(res).has.jsonbody()
        assert.same(json_table.message,
                    "schema violation (access_token_upstream_header, channel_token_upstream_header, " ..
                    "original_access_token_upstream_header and original_channel_token_upstream_header " ..
                    "should not have the same value.)")
    end)
  end)

  describe(fmt("%s - introspection - consumer", plugin_name), function()
    -- Sending opaque tokens require introspection. This test involves a fixture to return static
    -- results for introspection.

    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, nil, { plugin_name })

      assert(assert(bp.consumers:insert({
        username = "some_username"
      })))

      local route0 = bp.routes:insert({ paths = { "/introspection-consumer-claim" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route0,
        config = {
          -- to just test signing
          verify_access_token_signature = false,
          channel_token_optional = true,
          -- true is the default, but setting explicitly for clarity
          enable_access_token_introspection = true,
          access_token_introspection_endpoint = introspection_url,
          access_token_introspection_consumer_claim = { "username" }
        }
      }))
      local route1 = bp.routes:insert({ paths = { "/introspection-consumer-claim-fails" }, })
      assert(bp.plugins:insert({
        name = plugin_name,
        route = route1,
        config = {
          -- to just test signing
          verify_access_token_signature = false,
          channel_token_optional = true,
          -- true is the default, but setting explicitly for clarity
          enable_access_token_introspection = true,
          access_token_introspection_endpoint = introspection_url,
          access_token_introspection_consumer_claim = { "no-scope-found" }
        }
      }))

      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, introspection_fixture))
      --  = helpers.test_conf.nginx_err_logs
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

    it("returns 200 when introspection_consumer_claim finds a valid consumer", function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/introspection-consumer-claim",
        headers = {
          ["authorization"] = "valid_complex"
        }
      })
      assert.response(res).has.status(200)
      local username = assert.request(res).has.header("X-Consumer-Username")
      assert.is_equal(username, "some_username")
      assert.logfile().has.line("access token opaque")
      assert.logfile().has.line("introspecting token with http://127.0.0.1:10000/introspect")
      assert.logfile().has.line("access token introspected")
      assert.logfile().has.line("access token introspection expiry verification")
      assert.logfile().has_not.line("access token introspection consumer claim could not be found")
      assert.logfile().has.line("access token signing")
    end)

    it("returns 401 when introspection_consumer_claim and introspection_consumer_by are configured but consumer not found"
      , function()
      local res = assert(proxy_client:send {
        method = "get",
        path = "/introspection-consumer-claim-fails",
        headers = {
          ["authorization"] = "valid_complex"
        }
      })
      assert.response(res).has.status(403)
      assert.logfile().has.line("access token opaque")
      assert.logfile().has.line("access token introspected")
      assert.logfile().has.line("access token introspection expiry verification")
      assert.logfile().has.line("access token introspection consumer claim could not be found")
      assert.logfile().has_not.line("access token signing")
    end)

  end)
end
