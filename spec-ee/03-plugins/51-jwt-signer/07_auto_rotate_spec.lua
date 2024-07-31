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
local keys = require "kong.openid-connect.keys"
local cjson = require "cjson.safe"
local fmt = string.format

local plugin_name = "jwt-signer"
local test_user = "john"
local test_pswd = "12345678"

local function sign_token(ec_key)
  local now = ngx.time()
  local exp = now + 3600     -- 1 hour
  local token = {
    jwk = cjson.decode(ec_key),
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

local function verify_token(ec_key, credential)
  local err
  if not credential then
    return false, "no credential"
  end

  local token = string.sub(credential, 8)  -- "Bearer xxx"
  if not token then
    return false, "invalid credential"
  end

  local jwks
  jwks, err = cjson.decode('{"keys": [ ' .. ec_key .. ' ]}')
  if not jwks then
    return false, "failed to decode json" .. err
  end

  return jws.decode(token, {
    verify_signature = true,
    keys = keys.new({}, jwks.keys)
  })
end


local function get_request(proxy_client, path, header, credential)
  return assert(proxy_client:send {
    method = "GET",
    path = path,
    headers = {
      [header] = credential,
    }
  })
end


for _, strategy in helpers.all_strategies() do
  describe(fmt("%s - auto-rotate external jwks service [#%s]", plugin_name, strategy), function()
    local bp, db, proxy_client, proxy_client2
    local credential1, credential2, credential3
    local client_cert
    local rotate_period = 2
    -- we remove the `kid` intentionally to avoid rediscovery when the specified `kid` is not found.
    -- because 2 key sets (current and previous) will be stored, so we use 3 key sets to test.
    local ec_key1 = '{"kty":"EC","crv":"P-256","y":"kGe5DgSIycKp8w9aJmoHhB1sB3QTugfnRWm5nU_TzsY","alg":"ES256","x":"EVs_o5-uQbTjL3chynL4wXgUg2R9q9UU8I5mEovUf84","d":"evZzL1gdAFr88hb2OF_2NxApJCzGCEDdfSp6VQO30hw"}'
    local ec_key2 = '{"kty":"EC","crv":"P-256","y":"i8ep9dYI5gK1GIEdQOKztFCZgE9juH6hFmZjjbhH1Vg","alg":"ES256","x":"G4gFqcqlsGBt5ieBCZDykyI8NvyWl6x_YNaFrzdmb_U","d":"cyy1B1NVIG-OAXs6FxBknVNmzJZzXbL7ZSPP08bVKUo"}'
    local ec_key3 = '{"kty":"EC","crv":"P-256","y":"t6urIJox8ge1VAzqUFvsJlvcoJ48s32fec2gxOsUpyU","alg":"ES256","x":"hbdDTkNOZmyDnN1I-IJaqUinlp6EMF_90jK-Q-ZovD0","d":"5XbI_xvm5s2Xhg3GQEXFoQlOekO8DRUI4oYHSjsAGbk"}'
    credential1 = "Bearer " .. sign_token(ec_key1)
    credential2 = "Bearer " .. sign_token(ec_key2)
    credential3 = "Bearer " .. sign_token(ec_key3)

    local HTTP_SERVER_PORT = helpers.get_available_port()
    local jwks_uri = "https://localhost:" .. HTTP_SERVER_PORT .. "/jwks"
    local mock = http_mock.new(HTTP_SERVER_PORT, {
      ["/jwks"] = {
        access = [[
          local decode_base64 = ngx.decode_base64
          local re_gmatch = ngx.re.gmatch
          local re_match = ngx.re.match

          local function basic_auth()
            local authorization_header = ngx.req.get_headers()["authorization"]

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

          if not ngx.access_counts then
            ngx.access_counts = {}
          end
          local count = ngx.access_counts[ngx.var.uri] or 0
          ngx.access_counts[ngx.var.uri] = count + 1

          local keys_json
          -- in the order of ec_key1, ec_key2, ec_key3, ec_key1, ...
          if count % 3 == 0 then
            keys_json = '{"keys": [ ]] .. ec_key1 .. [[ ]}'
          elseif count % 3 == 1 then
            keys_json = '{"keys": [ ]] .. ec_key2 .. [[ ]}'
          else
            keys_json = '{"keys": [ ]] .. ec_key3 .. [[ ]}'
          end
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

      local route1 = bp.routes:insert({ paths = { "/access_jwks" } })
      local route2 = bp.routes:insert({ paths = { "/access_keyset" } })
      local route3 = bp.routes:insert({ paths = { "/channel_jwks" } })
      local route4 = bp.routes:insert({ paths = { "/channel_keyset" } })
      local route5 = bp.routes:insert({ paths = { "/rotation_failure" } })

      -- every plugin uses different uri to prevent different tests from interfering with each other
      bp.plugins:insert({
        name = plugin_name,
        route = route1,
        config = {
          verify_access_token_signature = true,
          access_token_jwks_uri = jwks_uri .. "/access_jwks",
          access_token_jwks_uri_client_username = test_user,
          access_token_jwks_uri_client_password = test_pswd,
          access_token_jwks_uri_client_certificate = { id = client_cert.id },
          access_token_jwks_uri_rotate_period = rotate_period,
          access_token_upstream_header = ngx.null,
          channel_token_optional = true,
        },
      })

      bp.plugins:insert({
        name = plugin_name,
        route = route2,
        config = {
          verify_access_token_signature = false,
          access_token_signing_algorithm = "ES256",
          access_token_upstream_header = "authorization:Bearer",
          access_token_keyset = jwks_uri .. "/access_keyset",
          access_token_keyset_client_username = test_user,
          access_token_keyset_client_password = test_pswd,
          access_token_keyset_client_certificate = { id = client_cert.id },
          access_token_keyset_rotate_period = rotate_period,
          channel_token_optional = true,
        },
      })

      bp.plugins:insert({
        name = plugin_name,
        route = route3,
        config = {
          verify_channel_token_signature = true,
          channel_token_jwks_uri = jwks_uri .. "/channel_jwks",
          channel_token_jwks_uri_client_username = test_user,
          channel_token_jwks_uri_client_password = test_pswd,
          channel_token_jwks_uri_client_certificate = { id = client_cert.id },
          channel_token_jwks_uri_rotate_period = rotate_period,
          channel_token_upstream_header = ngx.null,
          channel_token_request_header = "channel_authorization",
          access_token_optional = true,
        },
      })

      bp.plugins:insert({
        name = plugin_name,
        route = route4,
        config = {
          verify_channel_token_signature = false,
          channel_token_signing_algorithm = "ES256",
          channel_token_upstream_header = "channel_authorization:Bearer",
          channel_token_keyset = jwks_uri .. "/channel_keyset",
          channel_token_keyset_client_username = test_user,
          channel_token_keyset_client_password = test_pswd,
          channel_token_keyset_client_certificate = { id = client_cert.id },
          channel_token_keyset_rotate_period = rotate_period,
          channel_token_request_header = "channel_authorization",
          access_token_optional = true,
        },
      })

      bp.plugins:insert({
        name = plugin_name,
        route = route5,
        config = {
          verify_access_token_signature = true,
          access_token_jwks_uri = jwks_uri .. "/access_jwks_failure",
          access_token_jwks_uri_client_username = test_user,
          access_token_jwks_uri_client_password = "invalid_password",
          access_token_jwks_uri_client_certificate = { id = client_cert.id },
          access_token_jwks_uri_rotate_period = 3600,   -- a big period

          verify_channel_token_signature = true,
          channel_token_jwks_uri = jwks_uri .. "/channel_jwks_failure",
          channel_token_jwks_uri_client_username = test_user,
          channel_token_jwks_uri_client_password = "invalid_password",
          channel_token_jwks_uri_client_certificate = { id = client_cert.id },
          channel_token_jwks_uri_rotate_period = 3600,  -- a big period
          channel_token_request_header = "channel_authorization",

          access_token_signing_algorithm = "ES256",
          access_token_upstream_header = "authorization:Bearer",
          access_token_keyset = jwks_uri .. "/access_keyset_failure",
          access_token_keyset_client_username = test_user,
          access_token_keyset_client_password = "invalid_password",
          access_token_keyset_client_certificate = { id = client_cert.id },
          access_token_keyset_rotate_period = 3600,   -- a big period

          channel_token_signing_algorithm = "ES256",
          channel_token_upstream_header = "channel_authorization:Bearer",
          channel_token_keyset = jwks_uri .. "/channel_keyset_failure",
          channel_token_keyset_client_username = test_user,
          channel_token_keyset_client_password = "invalid_password",
          channel_token_keyset_client_certificate = { id = client_cert.id },
          channel_token_keyset_rotate_period = 3600,  -- a big period
        },
      })

      local yaml_file = helpers.make_yaml_file()
      assert(mock:start())
      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        declarative_config = strategy == "off" and yaml_file or nil,
        pg_host = strategy == "off" and "unknownhost.konghq.com" or nil,
        db_update_frequency = 0.1,
        nginx_worker_processes = 2,
      }))

      if strategy ~= "off" then
        assert(helpers.start_kong({
          database   = strategy,
          plugins    = plugin_name,
          declarative_config = strategy == "off" and yaml_file or nil,
          pg_host = strategy == "off" and "unknownhost.konghq.com" or nil,
          db_update_frequency = 0.1,
          nginx_worker_processes = 2,
          prefix = "node2",
          proxy_listen = "127.0.0.1:9100",
          admin_listen = "127.0.0.1:9101",
        }))
      end
    end)

    lazy_teardown(function()
      assert(db:truncate("jwt_signer_jwks"))
      assert(db:truncate("certificates"))
      assert(db:truncate("plugins"))
      assert(db:truncate("services"))
      assert(db:truncate("routes"))
      helpers.stop_kong()
      if strategy ~= "off" then
        helpers.stop_kong("node2")
      end
      mock:stop()
    end)

    it("should use a short delay on failure", function()
      assert.with_timeout(10)
      .eventually(function()
        assert.logfile().has.line("start auto-rotating jwks for " .. jwks_uri .. "/access_jwks_failure", true, 0)
        assert.logfile().has.line("loading jwks from " .. jwks_uri .. "/access_jwks_failure failed", true, 0)
        assert.logfile().has.line("the next rotation for " .. jwks_uri .. "/access_jwks_failure will be after 30s", true, 0)
        assert.logfile().has.line("start auto-rotating jwks for " .. jwks_uri .. "/access_keyset_failure", true, 0)
        assert.logfile().has.line("loading jwks from " .. jwks_uri .. "/access_keyset_failure failed", true, 0)
        assert.logfile().has.line("the next rotation for " .. jwks_uri .. "/access_keyset_failure will be after 30s", true, 0)
        assert.logfile().has.line("start auto-rotating jwks for " .. jwks_uri .. "/channel_jwks_failure", true, 0)
        assert.logfile().has.line("loading jwks from " .. jwks_uri .. "/channel_jwks_failure failed", true, 0)
        assert.logfile().has.line("the next rotation for " .. jwks_uri .. "/channel_jwks_failure will be after 30s", true, 0)
        assert.logfile().has.line("start auto-rotating jwks for " .. jwks_uri .. "/channel_keyset_failure", true, 0)
        assert.logfile().has.line("loading jwks from " .. jwks_uri .. "/channel_keyset_failure failed", true, 0)
        assert.logfile().has.line("the next rotation for " .. jwks_uri .. "/channel_keyset_failure will be after 30s", true, 0)
      end)
      .has_no_error("get the expected logs")
    end)

    for k, header in pairs({access = "authorization", channel = "channel_authorization"}) do
      if strategy == "off" then
        it(fmt("should rotate jwks properly for %s_token_jwks_uri", k), function()
          local path = fmt("/%s_jwks", k)
          local ress = {}
          local succ_count = 0
          assert
            .with_timeout((rotate_period + 1) * 6)
            .eventually(function()
              local res
              proxy_client = helpers.proxy_client()
              if not ress[1] then
                res = get_request(proxy_client, path, header, credential1)
                if res.status == 200 then
                  ress[1] = true
                  succ_count = succ_count + 1
                end
              end

              if not ress[2] then
                res = get_request(proxy_client, path, header, credential2)
                if res.status == 200 then
                  ress[2] = true
                  succ_count = succ_count + 1
                end
              end

              if not ress[3] then
                res = get_request(proxy_client, path, header, credential3)
                if res.status == 200 then
                  ress[3] = true
                  succ_count = succ_count + 1
                end
              end

              proxy_client:close()
              assert.same(3, succ_count)
            end)
            .has_no_error("each key gets a turn because of rotation")
        end)

        it(fmt("should rotate jwks properly for %s_token_keyset", k), function()
          local path = fmt("/%s_keyset", k)
          local ress = {}
          local succ_count = 0
          assert
            .with_timeout((rotate_period + 1) * 6)
            .eventually(function()
              local res
              proxy_client = helpers.proxy_client()

              if not ress[1] then
                res = get_request(proxy_client, path, header, credential1)
                local body = assert.res_status(200, res)
                local json = cjson.decode(body)
                if verify_token(ec_key1, json.headers[header]) then
                  ress[1] = true
                  succ_count = succ_count + 1
                end
              end

              if not ress[2] then
                res = get_request(proxy_client, path, header, credential1)
                local body = assert.res_status(200, res)
                local json = cjson.decode(body)
                if verify_token(ec_key2, json.headers[header]) then
                  ress[2] = true
                  succ_count = succ_count + 1
                end
              end

              if not ress[3] then
                res = get_request(proxy_client, path, header, credential1)
                local body = assert.res_status(200, res)
                local json = cjson.decode(body)
                if verify_token(ec_key3, json.headers[header]) then
                  ress[3] = true
                  succ_count = succ_count + 1
                end
              end

              proxy_client:close()
              assert.same(3, succ_count)
            end)
            .has_no_error("each key gets a turn because of rotation")
        end)

      else  -- strategy == "off"
        it(fmt("should rotate jwks properly for %s_token_jwks_uri", k), function()
          local path = fmt("/%s_jwks", k)
          local ress = {}
          local succ_count = 0
          assert
            .with_timeout((rotate_period + 1) * 6)
            .eventually(function()
              local res
              proxy_client = helpers.proxy_client()
              proxy_client2 = helpers.proxy_client(nil, 9100)
              if not ress[1] then
                res = get_request(proxy_client, path, header, credential1)
                if res.status == 200 then
                  ress[1] = true
                  succ_count = succ_count + 1
                end
              end

              if not ress[2] then
                res = get_request(proxy_client2, path, header, credential1)
                if res.status == 200 then
                  ress[2] = true
                  succ_count = succ_count + 1
                end
              end

              if not ress[3] then
                res = get_request(proxy_client, path, header, credential2)
                if res.status == 200 then
                  ress[3] = true
                  succ_count = succ_count + 1
                end
              end

              if not ress[4] then
                res = get_request(proxy_client2, path, header, credential2)
                if res.status == 200 then
                  ress[4] = true
                  succ_count = succ_count + 1
                end
              end

              if not ress[5] then
                res = get_request(proxy_client, path, header, credential3)
                if res.status == 200 then
                  ress[5] = true
                  succ_count = succ_count + 1
                end
              end

              if not ress[6] then
                res = get_request(proxy_client2, path, header, credential3)
                if res.status == 200 then
                  ress[6] = true
                  succ_count = succ_count + 1
                end
              end

              proxy_client:close()
              proxy_client2:close()

              assert.same(6, succ_count)
            end)
            .has_no_error("each key gets a turn because of rotation")
        end)

        it(fmt("should rotate jwks properly for %s_token_keyset", k), function()
          local path = fmt("/%s_keyset", k)
          local ress = {}
          local succ_count = 0
          assert
            .with_timeout((rotate_period + 1) * 6)
            .eventually(function()
              local res
              proxy_client = helpers.proxy_client()
              proxy_client2 = helpers.proxy_client(nil, 9100)

              if not ress[1] then
                res = get_request(proxy_client, path, header, credential1)
                local body = assert.res_status(200, res)
                local json = cjson.decode(body)
                if verify_token(ec_key1, json.headers[header]) then
                  ress[1] = true
                  succ_count = succ_count + 1
                end
              end

              if not ress[2] then
                res = get_request(proxy_client2, path, header, credential1)
                local body = assert.res_status(200, res)
                local json = cjson.decode(body)
                if verify_token(ec_key1, json.headers[header]) then
                  ress[2] = true
                  succ_count = succ_count + 1
                end
              end

              if not ress[3] then
                res = get_request(proxy_client, path, header, credential1)
                local body = assert.res_status(200, res)
                local json = cjson.decode(body)
                if verify_token(ec_key2, json.headers[header]) then
                  ress[3] = true
                  succ_count = succ_count + 1
                end
              end

              if not ress[4] then
                res = get_request(proxy_client2, path, header, credential1)
                local body = assert.res_status(200, res)
                local json = cjson.decode(body)
                if verify_token(ec_key2, json.headers[header]) then
                  ress[4] = true
                  succ_count = succ_count + 1
                end
              end

              if not ress[5] then
                res = get_request(proxy_client, path, header, credential1)
                local body = assert.res_status(200, res)
                local json = cjson.decode(body)
                if verify_token(ec_key3, json.headers[header]) then
                  ress[5] = true
                  succ_count = succ_count + 1
                end
              end

              if not ress[6] then
                res = get_request(proxy_client2, path, header, credential1)
                local body = assert.res_status(200, res)
                local json = cjson.decode(body)
                if verify_token(ec_key3, json.headers[header]) then
                  ress[6] = true
                  succ_count = succ_count + 1
                end
              end

              proxy_client:close()
              proxy_client2:close()

              assert.same(6, succ_count)
            end)
            .has_no_error("each key gets a turn because of rotation")
        end)
      end -- strategy == "off"
    end
  end)
end
