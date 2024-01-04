-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local http_mock = require "spec.helpers.http_mock"

local PLUGIN_NAME = "openid-connect"
local time = ngx.time

local PASSWORD_CREDENTIAL = "Basic am9objpkb2U="

for _, strategy in helpers.all_strategies() do
  describe("token exp strategy: #" .. strategy, function()
    local proxy_client
    local token_lifespan = 2    --a short token lifespan for easy testing
    local HTTP_SERVER_PORT = helpers.get_available_port()
    local issuer_url = "http://localhost:" .. HTTP_SERVER_PORT .. "/issuer"
    local token_url = "http://localhost:" .. HTTP_SERVER_PORT .. "/token"

    local mock = http_mock.new(HTTP_SERVER_PORT, {
      ["/token"] = {
        access = [[
          package.path = package.path .. ";/usr/local/share/lua/5.1/?.ljbc;/usr/local/share/lua/5.1/?/init.ljbc"
          local jws = require "kong.openid-connect.jws"
          local codec = require "kong.openid-connect.codec"
          local base64url = codec.base64url

          ngx.header.content_type = "application/json"

          local b64key = base64url.encode("my_secret_key")
          local now = ngx.time()
          local exp = now  + ]] .. token_lifespan .. [[

          local token = {
            jwk = {
              kty = "oct",
              k = b64key,
              alg = "HS256",
            },
            header = {
              typ = "JWT",
              alg = "HS256",
            },
            payload = {
              sub = "1234567890",
              name = "John Doe",
              exp = exp,
              iat = now,
            },
          }

          local access_token, err = jws.encode(token)
          if not access_token then
              print(err)
          end
          local json = '{ "exp": ' .. exp .. ', "token_type": "Bearer", "access_token": "' .. access_token .. '" }'

          ngx.print(json)
          ngx.exit(200)
        ]]
      },
      ["/issuer/.well-known/openid-configuration"] = {
        access = [[
          ngx.header.content_type = "application/json"
          local json = '{ "issuer": "' .. issuer_url .. '" }'
          ngx.print(json)
          ngx.exit(200)
        ]]
      }
    })

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, {
        PLUGIN_NAME,
      })

      local service = bp.services:insert {
        name = PLUGIN_NAME,
        path = "/anything"
      }

      local route = bp.routes:insert {
        service = service,
        paths   = { "/test" },
      }

      bp.plugins:insert {
        route   = route,
        name    = PLUGIN_NAME,
        config  = {
          issuer    = issuer_url,
          client_id = {
            "kong",
          },
          client_secret = {
            "kong-secret",
          },
          auth_methods = {
            "password",
          },
          cache_tokens = true,
          token_endpoint = token_url,
          ignore_signature = {
            "password",
          },
          enable_hs_signatures = true,
        },
      }

      assert(mock:start())
      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins    = "bundled," .. PLUGIN_NAME,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      mock:stop()
    end)

    it("should always be authenticated successfully including the boundary case where exp == ttl.now", function()
      local start = time()
      -- two periods to make sure the boundary condition is covered.
      while time() < start + token_lifespan * 2 do
        proxy_client = assert(helpers.proxy_client())
        local res = assert(proxy_client:send({
          method = "GET",
          path = "/test",
          headers = {
            -- an arbitrary credential is fine as the token endpoint won't verify
            ["Authorization"] = PASSWORD_CREDENTIAL,
          },
        }))
        assert.response(res).has.status(200)
        proxy_client:close()
        ngx.sleep(0.1)
      end
    end)
  end)
end

