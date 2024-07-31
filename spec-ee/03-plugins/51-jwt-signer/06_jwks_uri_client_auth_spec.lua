-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local ssl_fixtures = require "spec.fixtures.ssl"
local http_mock = require "spec.helpers.http_mock"
local jws = require "kong.openid-connect.jws"
local json = require "cjson.safe"
local fmt = string.format

local plugin_name = "jwt-signer"
local test_user = "john"
local test_pswd = "12345678"

local function sign_token(ec_key)
  local now = ngx.time()
  local exp = now + 600
  local token = {
    jwk = json.decode(ec_key),
    header = {
      typ = "JWT",
      alg = "ES256",
    },
    payload = {
      sub = "1234567890",
      name = "John Doe",
      exp = exp,
      now = now,
    },
  }

  return assert(jws.encode(token))
end

for _, strategy in helpers.all_strategies() do
  describe(fmt("%s - client auth to external jwks service [#%s]", plugin_name, strategy), function()
    local bp, db, admin_client, proxy_client
    local credential
    local client_cert
    local ec_key = '{"kty":"EC","crv":"P-256","y":"kGe5DgSIycKp8w9aJmoHhB1sB3QTugfnRWm5nU_TzsY","alg":"ES256","kid":"19J8y7Zprt2-QKLjF2I5pVk0OELX6cY2AfaAv1LC_w8","x":"EVs_o5-uQbTjL3chynL4wXgUg2R9q9UU8I5mEovUf84","d":"evZzL1gdAFr88hb2OF_2NxApJCzGCEDdfSp6VQO30hw"}'
    local HTTP_SERVER_PORT = helpers.get_available_port()
    local jwks_uri = "https://localhost:" .. HTTP_SERVER_PORT .. "/jwks"
    local mock = http_mock.new(HTTP_SERVER_PORT, {
      ["/jwks"] = {
        access = [[
          local decode_base64 = ngx.decode_base64
          local re_gmatch = ngx.re.gmatch
          local re_match = ngx.re.match

          local function basic_auth()
            local authorization_header = ngx.req.get_headers()["Authorization"]

            if authorization_header then
              local iterator, iter_err = re_gmatch(authorization_header, "\\s*[Bb]asic\\s*(.+)", "oj")
              if not iterator then
                print("invalid authorization header")
                return false
              end

              local m, err = iterator()
              if err then
                print("internal error")
                return false
              end

              if m and m[1] then
                local decoded_basic = decode_base64(m[1])
                if decoded_basic then
                  local basic_parts, err = re_match(decoded_basic, "([^:]+):(.+)", "oj")
                  if err then
                    print("Failed to ")
                    return
                  end

                  if not basic_parts then
                    print("header is ill-formed")
                    return false
                  end

                  local username = basic_parts[1]
                  local password = basic_parts[2]

                  if username == "]] .. test_user .. [[" and password == "]] .. test_pswd .. [[" then
                    return true
                  end
                end
              end
            else
              print("no authorization header")
            end

            print("invalid credential")
            return false
          end

          local res = basic_auth()
          if not res then
            ngx.exit(401)
          end

          local keys_json = '{"keys": [ ]] .. ec_key .. [[ ]}'
          ngx.header.content_type = "application/jwk-set+json"
          ngx.print(keys_json)
          ngx.exit(200)
        ]],
      },
    }, {
      tls = "true",
      directives = {
        "ssl_client_certificate ../../spec/fixtures/mtls_certs/ca.crt;",
        "ssl_verify_client      on;",
        "ssl_session_tickets    off;",
        "ssl_session_cache      off;",
        "keepalive_requests     0;",
      },
    })

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, {
        "routes",
        "services",
        "plugins",
        "certificates",
        "jwt_signer_jwks",
      }, { plugin_name })

      client_cert = bp.certificates:insert {
        cert = ssl_fixtures.cert_client,
        key  = ssl_fixtures.key_client,
      }

      local route1 = bp.routes:insert({ paths = { "/access_jwks_pass" } })
      local route2 = bp.routes:insert({ paths = { "/access_jwks_mtls_fail" } })
      local route3 = bp.routes:insert({ paths = { "/access_jwks_basic_fail" } })
      local route4 = bp.routes:insert({ paths = { "/access_keyset_pass" } })
      local route5 = bp.routes:insert({ paths = { "/access_keyset_mtls_fail" } })
      local route6 = bp.routes:insert({ paths = { "/access_keyset_basic_fail" } })
      local route7 = bp.routes:insert({ paths = { "/channel_jwks_pass" } })
      local route8 = bp.routes:insert({ paths = { "/channel_jwks_mtls_fail" } })
      local route9 = bp.routes:insert({ paths = { "/channel_jwks_basic_fail" } })
      local route10 = bp.routes:insert({ paths = { "/channel_keyset_pass" } })
      local route11 = bp.routes:insert({ paths = { "/channel_keyset_mtls_fail" } })
      local route12 = bp.routes:insert({ paths = { "/channel_keyset_basic_fail" } })

      local route13 = bp.routes:insert({ paths = { "/access_jwks_pass_for_rotating" } })

      -- every plugin uses different uri to prevent different tests from interfering with each other
      bp.plugins:insert({
        name = plugin_name,
        route = route1,
        config = {
          verify_access_token_signature = true,
          access_token_jwks_uri = jwks_uri .. "/access_jwks_pass",
          access_token_jwks_uri_client_username = test_user,
          access_token_jwks_uri_client_password = test_pswd,
          access_token_jwks_uri_client_certificate = { id = client_cert.id },
          access_token_upstream_header = ngx.null,
          channel_token_optional = true,
        },
      })

      bp.plugins:insert({
        name = plugin_name,
        route = route2,
        config = {
          verify_access_token_signature = true,
          access_token_jwks_uri = jwks_uri .. "/access_jwks_mtls_fail",
          access_token_jwks_uri_client_username = test_user,
          access_token_jwks_uri_client_password = test_pswd,
          access_token_upstream_header = ngx.null,
          channel_token_optional = true,
        },
      })

      bp.plugins:insert({
        name = plugin_name,
        route = route3,
        config = {
          verify_access_token_signature = true,
          access_token_jwks_uri = jwks_uri .. "/access_jwks_basic_fail",
          access_token_jwks_uri_client_certificate = { id = client_cert.id },
          access_token_upstream_header = ngx.null,
          channel_token_optional = true,
        },
      })

      bp.plugins:insert({
        name = plugin_name,
        route = route4,
        config = {
          verify_access_token_signature = false,
          access_token_signing_algorithm = "ES256",
          access_token_upstream_header = "Authorization:Bearer",
          access_token_keyset = jwks_uri .. "/access_keyset_pass",
          access_token_keyset_client_username = test_user,
          access_token_keyset_client_password = test_pswd,
          access_token_keyset_client_certificate = { id = client_cert.id },
          channel_token_optional = true,
        },
      })

      bp.plugins:insert({
        name = plugin_name,
        route = route5,
        config = {
          verify_access_token_signature = false,
          access_token_signing_algorithm = "ES256",
          access_token_upstream_header = "Authorization:Bearer",
          access_token_keyset = jwks_uri .. "/access_keyset_mtls_fail",
          access_token_keyset_client_username = test_user,
          access_token_keyset_client_password = test_pswd,
          channel_token_optional = true,
        },
      })

      bp.plugins:insert({
        name = plugin_name,
        route = route6,
        config = {
          verify_access_token_signature = false,
          access_token_signing_algorithm = "ES256",
          access_token_upstream_header = "Authorization:Bearer",
          access_token_keyset = jwks_uri .. "/access_keyset_basic_fail",
          access_token_keyset_client_certificate = { id = client_cert.id },
          channel_token_optional = true,
        },
      })

      bp.plugins:insert({
        name = plugin_name,
        route = route7,
        config = {
          verify_channel_token_signature = true,
          channel_token_jwks_uri = jwks_uri .. "/channel_jwks_pass",
          channel_token_jwks_uri_client_username = test_user,
          channel_token_jwks_uri_client_password = test_pswd,
          channel_token_jwks_uri_client_certificate = { id = client_cert.id },
          channel_token_upstream_header = ngx.null,
          channel_token_request_header = "Channel_Authorization",
          access_token_optional = true,
        },
      })

      bp.plugins:insert({
        name = plugin_name,
        route = route8,
        config = {
          verify_channel_token_signature = true,
          channel_token_jwks_uri = jwks_uri .. "/channel_jwks_mtls_fail",
          channel_token_jwks_uri_client_username = test_user,
          channel_token_jwks_uri_client_password = test_pswd,
          channel_token_upstream_header = ngx.null,
          channel_token_request_header = "Channel_Authorization",
          access_token_optional = true,
        },
      })

      bp.plugins:insert({
        name = plugin_name,
        route = route9,
        config = {
          verify_channel_token_signature = true,
          channel_token_jwks_uri = jwks_uri .. "/channel_jwks_basic_fail",
          channel_token_jwks_uri_client_certificate = { id = client_cert.id },
          channel_token_upstream_header = ngx.null,
          channel_token_request_header = "Channel_Authorization",
          access_token_optional = true,
        },
      })

      bp.plugins:insert({
        name = plugin_name,
        route = route10,
        config = {
          verify_channel_token_signature = false,
          channel_token_signing_algorithm = "ES256",
          channel_token_upstream_header = "Channel_Authorization:Bearer",
          channel_token_keyset = jwks_uri .. "/channel_keyset_pass",
          channel_token_keyset_client_username = test_user,
          channel_token_keyset_client_password = test_pswd,
          channel_token_keyset_client_certificate = { id = client_cert.id },
          channel_token_request_header = "Channel_Authorization",
          access_token_optional = true,
        },
      })

      bp.plugins:insert({
        name = plugin_name,
        route = route11,
        config = {
          verify_channel_token_signature = false,
          channel_token_signing_algorithm = "ES256",
          channel_token_upstream_header = "Channel_Authorization:Bearer",
          channel_token_keyset = jwks_uri .. "/channel_keyset_mtls_fail",
          channel_token_keyset_client_username = test_user,
          channel_token_keyset_client_password = test_pswd,
          channel_token_request_header = "Channel_Authorization",
          access_token_optional = true,
        },
      })

      bp.plugins:insert({
        name = plugin_name,
        route = route12,
        config = {
          verify_channel_token_signature = false,
          channel_token_signing_algorithm = "ES256",
          channel_token_upstream_header = "Channel_Authorization:Bearer",
          channel_token_keyset = jwks_uri .. "/channel_keyset_basic_fail",
          channel_token_keyset_client_certificate = { id = client_cert.id },
          channel_token_request_header = "Channel_Authorization",
          access_token_optional = true,
        },
      })

      bp.plugins:insert({
        name = plugin_name,
        route = route13,
        config = {
          verify_access_token_signature = true,
          access_token_jwks_uri = jwks_uri .. "/access_jwks_pass_for_rotating",
          access_token_jwks_uri_client_username = test_user,
          access_token_jwks_uri_client_password = test_pswd,
          access_token_jwks_uri_client_certificate = { id = client_cert.id },
          access_token_upstream_header = ngx.null,
          channel_token_optional = true,
        },
      })

      assert(mock:start())
      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
        pg_host = strategy == "off" and "unknownhost.konghq.com" or nil,
      }))
    end)

    lazy_teardown(function()
      assert(db:truncate("jwt_signer_jwks"))
      assert(db:truncate("certificates"))
      assert(db:truncate("plugins"))
      assert(db:truncate("services"))
      assert(db:truncate("routes"))
      helpers.stop_kong()
      mock:stop()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
      credential = "Bearer " .. sign_token(ec_key)
    end)

    after_each(function()
      helpers.clean_logfile()
      if proxy_client then
        proxy_client:close()
      end
    end)

    for k, header in pairs({access = "Authorization", channel = "Channel_Authorization"}) do
      it(fmt("should succeed to fetch jwks from %s_token_jwks_uri when both mtls and basic credentials are provided", k), function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = fmt("/%s_jwks_pass", k),
          headers = {
            [header] = credential,
          }
        })
        assert.response(res).has.status(200)
        assert.logfile().has.line(fmt("loading jwks from %s/%s_jwks_pass", jwks_uri, k), true)
      end)

      it(fmt("should fail to fetch jwks from %s_token_jwks_uri when mtls credential isn't provided", k), function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = fmt("/%s_jwks_mtls_fail", k),
          headers = {
            [header] = credential,
          }
        })
        assert.response(res).has.status(401)
        assert.logfile().has.line(fmt("loading jwks from %s/%s_jwks_mtls_fail failed: invalid status code received from the jwks endpoint (400)", jwks_uri, k), true)
      end)

      it(fmt("should fail to fetch jwks from %s_token_jwks_uri when basic credential isn't provided", k), function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = fmt("/%s_jwks_basic_fail", k),
          headers = {
            [header] = credential,
          }
        })
        assert.response(res).has.status(401)
        assert.logfile().has.line(fmt("loading jwks from %s/%s_jwks_basic_fail failed: invalid status code received from the jwks endpoint (401)", jwks_uri, k), true)
      end)

      it(fmt("should succeed to fetch jwks from %s_token_keyset when both mtls and basic credentials are provided", k), function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = fmt("/%s_keyset_pass", k),
          headers = {
            [header] = credential,
          }
        })
        assert.response(res).has.status(200)
        assert.logfile().has.line(fmt("loading jwks from %s/%s_keyset_pass", jwks_uri, k), true)
      end)

      it(fmt("should fail to fetch jwks from %s_token_keyset when mtls credentials isn't provided", k), function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = fmt("/%s_keyset_mtls_fail", k),
          headers = {
            [header] = credential,
          }
        })
        assert.response(res).has.status(500)
        assert.logfile().has.line(fmt("loading jwks from %s/%s_keyset_mtls_fail failed: invalid status code received from the jwks endpoint (400)", jwks_uri, k), true)
      end)

      it(fmt("should fail to fetch jwks from %s_token_keyset when basic credentials isn't provided", k), function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = fmt("/%s_keyset_basic_fail", k),
          headers = {
            [header] = credential,
          }
        })
        assert.response(res).has.status(500)
        assert.logfile().has.line(fmt("loading jwks from %s/%s_keyset_basic_fail failed: invalid status code received from the jwks endpoint (401)", jwks_uri, k), true)
      end)
    end

    if strategy ~= "off" then
      it("can pass mtls and basic credentials via the request parameters when rotating jwks by Admin API", function()
        local name = jwks_uri .. "/access_jwks_pass_for_rotating"
        local urlencoded_name = ngx.escape_uri(name)

        -- load once first to make sure the jwks exists
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/access_jwks_pass_for_rotating",
          headers = {
            ["Authorization"] = credential,
          },
        })
        assert.response(res).has.status(200)

        -- should succeed to rotate the jwks when both mtls and basic credentials are provided
        admin_client = helpers.admin_client()
        res = assert(admin_client:send {
          method = "POST",
          path = fmt("/jwt-signer/jwks/%s/rotate", urlencoded_name),
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            client_username = test_user,
            client_password = test_pswd,
            client_certificate = { id = client_cert.id },
          },
        })
        assert.res_status(200, res)
        assert.logfile().has.line(fmt("rotating jwks for %s/access_jwks_pass_for_rotating", jwks_uri), true)
        admin_client:close()

        -- should fail to rotate the jwks when mtls credentials isn't provided
        admin_client = helpers.admin_client()
        res = assert(admin_client:send {
          method = "POST",
          path = fmt("/jwt-signer/jwks/%s/rotate", urlencoded_name),
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            client_username = test_user,
            client_password = test_pswd,
          },
        })
        assert.res_status(500, res)
        assert.logfile().has.line(fmt("rotating jwks for %s/access_jwks_pass_for_rotating failed: invalid status code received from the jwks endpoint (400)", jwks_uri), true)
        admin_client:close()

        -- should fail to rotate the jwks when basic credentials isn't provided
        admin_client = helpers.admin_client()
        res = assert(admin_client:send {
          method = "POST",
          path = fmt("/jwt-signer/jwks/%s/rotate", urlencoded_name),
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            client_certificate = { id = client_cert.id },
          },
        })
        assert.res_status(500, res)
        assert.logfile().has.line(fmt("rotating jwks for %s/access_jwks_pass_for_rotating failed: invalid status code received from the jwks endpoint (401)", jwks_uri), true)
        admin_client:close()
      end)
    end
  end)
end
