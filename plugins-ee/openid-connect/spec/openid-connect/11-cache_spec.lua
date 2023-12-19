-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local PLUGIN_NAME = "openid-connect"

for _, strategy in helpers.all_strategies() do
  describe("cache test with strategy: #" .. strategy, function()
    local proxy_client
    local bearer_token = "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6IlE1THdMS18wM2xuQkg2NXhXQXVoVVNkQ2NXOXJFaUgxTU1QR2ZWOUx4SWcifQ.eyJleHAiOjE2OTk2NTc3MjcsImlhdCI6MTY5OTA1MjkyNywiaXNzIjoiZm9tbS1qd3QtY2xpIiwicm9sZXMiOlsiZGVtbyJdLCJ1c2VybmFtZSI6ImZvbW0ifQ.p_VxYA7V5oymW1U9fiaAaay9rxtPafBFatOGEFV9OpNomK5PAqmW3u78tzfVdBqt5ICAYSPsmLC75DdHGtjY0LrL6zFQ7bPg79AWjD9j-jArraVr8XH6PkLJElYJ9d-WqjwvHIzk6CpWdUie-eR-CZ1w9S9F9vfLF4ZihwWFFUIQLcZxcELtKW6LPEt5KSLwoUSg4GLJMq0FflBFPe7gyIA_7EwK9K0MHjc7bfzEijmzUMDei_suSC9N6VsqgirPSZJeS0kGnc7PU3KuXzxN1ytEmxLp6BUiL4NXgTsCHM7BhaLZsoEZ30a_Uso839e9mb0vE7_QSA1uGoxPXNN3ZQ"
    local credential = "Bearer " .. bearer_token

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, {
        PLUGIN_NAME, "request-termination",
      })

      local service = bp.services:insert {
        name = PLUGIN_NAME,
        path = "/anything"
      }
      local test_route = bp.routes:insert {
        service = service,
        paths   = { "/test" },
      }

      local jwk_route = bp.routes:insert {
        service = service,
        paths   = { "/jwk" },
      }

      local jwk_uri = "http://" .. helpers.get_proxy_ip() .. ":" .. helpers.get_proxy_port() .. "/jwk"

      local config = {
        issuer    = jwk_uri,
        auth_methods = {
          "bearer"
        },
        issuers_allowed = {
          "fomm-jwt-cli",
          "fomm-jwtcrypto",
        },
        extra_jwks_uris = {
          jwk_uri,
        },
      }

      bp.plugins:insert {
        route   = test_route,
        name    = PLUGIN_NAME,
        config  = config,
      }

      bp.plugins:insert {
        route = jwk_route,
        name = "request-termination",
        config = {
          body = '{"keys":[{"kty":"RSA","kid":"Q5LwLK_03lnBH65xWAuhUSdCcW9rEiH1MMPGfV9LxIg","n":"3Yx3pOw1zBFDI2zzlrKBf1ZJV-wEwXeWnltcgPJ6nZ9Ye_ctI-I3tKTuM9qPTNKbBXSCfhX9UpC5JlfNcU1eqQdJqS4QMDkn2weiyfZvkk4eD5oOa9HgOoM1SkdzOXqmQHpcnyVV-dOSRmSktbB1RX4VTz8gzNV3HQDhQK8vXgcILmn3Qr3xL_5QDKon_TCqrHMFFsMbSehBbB5pZdsI3QbPgkru9za-0xCmATCzPtmJ0fnRx1lTMoXnKpjIvJK78tdDTp5ejuX_hVsRYD7fzX5o79z_LWJjID9AocxP6K34vxtlX6es8yeRJNJIwsjED9nYHhMMbSRPWAUlDfbivw","e":"AQAB","alg":"RS256"}]}',
          content_type = "application/json",
          status_code = 200,
        }
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins    = "bundled," .. PLUGIN_NAME,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      helpers.clean_logfile()

      if proxy_client then
        proxy_client:close()
      end
    end)

    it("should fetch jwks successfully", function()
      local res = assert(proxy_client:send({
        method = "GET",
        path = "/test",
        headers = {
          ["Authorization"] = credential,
        },
      }))
      assert.logfile().has.no.line("no keys found (falling back to empty keys)", true)

      -- 401 because the token has expired, which means the signature has been verified
      -- using the key fetched from the extra_jwk_uri
      assert.response(res).has.status(401)
      assert.logfile().has.line("invalid exp claim (1699657727) was specified for access token", true)
    end)
  end)
end
