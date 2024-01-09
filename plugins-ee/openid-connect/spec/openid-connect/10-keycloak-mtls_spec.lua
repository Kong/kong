-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ngx_ssl = require "ngx.ssl"
local tablex = require "pl.tablex"

local helpers = require "spec.helpers"
local http_mock = require "spec.helpers.http_mock"
local fixtures_certificates = require "spec.openid-connect.fixtures.certificates"

local pl_file = require "pl.file"
local cjson = require "cjson"


local PLUGIN_NAME = "openid-connect"
local KONG_HOSTNAME = "kong"
local PROXY_PORT_HTTPS = 8000
local UPSTREAM_PORT = helpers.get_available_port()
local USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/93.0.4577.63 Safari/537.36" -- luacheck: ignore

-- Keycloak:
local KEYCLOAK_HOST = "keycloak"
local KEYCLOAK_SSL_PORT = 8443
local REALM_PATH = "/realms/demo"
local ISSUER_SSL_URL = "https://" .. KEYCLOAK_HOST .. ":" .. KEYCLOAK_SSL_PORT .. REALM_PATH .. "/.well-known/openid-configuration"
---- Clients:
local KONG_CLIENT_ID = "kong"
local KONG_CLIENT_SECRET = "X5DGMNBb6NjEp595L9h5Wb2x7DC4jvwE"
local TLS_AUTH_CLIENT_ID = "kong-client-tls-auth"
---- Users:
local USERNAME = "john"
local PASSWORD = "doe"
local PASSWORD_CREDENTIALS = "Basic " .. ngx.encode_base64(USERNAME .. ":" .. PASSWORD)


-- Certificates:
local current_file = debug.getinfo(1, "S").source:sub(2)
local plugin_dir = current_file:match("(.*/)") .. "../../"
local CERT_ROOT_FOLDER = plugin_dir .. "/.pongo/"

local ROOT_CA_CERT = fixtures_certificates.ROOT_CA_CERT
local INTERMEDIATE_CA_CERT = fixtures_certificates.INTERMEDIATE_CA_CERT

---- x5t_s256 hh_XBSxIT3qG46n5igJA0MsFEgXosYoWvzeRZfRCknY
local USER_CERT_STR = fixtures_certificates.USER_CERT_STR
local USER_KEY_STR = fixtures_certificates.USER_KEY_STR

local USER_CERT = ngx_ssl.parse_pem_cert(USER_CERT_STR)
local USER_KEY = ngx_ssl.parse_pem_priv_key(USER_KEY_STR)

---- x5t_s256 S7mEqyMUtjPZ-xK9HqK2sEoeFjNOz0IB7IGY_KzwQIE
local USER_CERT_STR_2 = fixtures_certificates.USER_CERT_STR_2
local USER_KEY_STR_2 = fixtures_certificates.USER_KEY_STR_2

local USER_CERT_2 = ngx_ssl.parse_pem_cert(USER_CERT_STR_2)
local USER_KEY_2 = ngx_ssl.parse_pem_priv_key(USER_KEY_STR_2)

---- key generated with a same CA to the correct one
---- x5t_s256 oDLR7Uo02EQ928ECU87wRgGmZU8-9s_kf06OfdiglAo
local RANDOM_CERT = fixtures_certificates.RANDOM_CERT
local RANDOM_KEY = fixtures_certificates.RANDOM_KEY

local RANDOM_SSL_CLIENT_CERT = ngx_ssl.parse_pem_cert(RANDOM_CERT)
local RANDOM_SSL_CLIENT_PRIV_KEY = ngx_ssl.parse_pem_priv_key(RANDOM_KEY)


local function get_jwt_from_token_endpoint()
  local path = REALM_PATH .. "/protocol/openid-connect/token"

  local keycloak_client = helpers.http_client({
    scheme = "https",
    host = KEYCLOAK_HOST,
    port = KEYCLOAK_SSL_PORT,
    ssl_verify = false,
    ssl_client_cert = USER_CERT,
    ssl_client_priv_key = USER_KEY,
  })

  local res = assert(keycloak_client:send {
    method = "POST",
    path = path,
    headers = {
      ["Content-Type"] = "application/x-www-form-urlencoded",
    },
    body = ngx.encode_args({
      client_id = KONG_CLIENT_ID,
      client_secret = KONG_CLIENT_SECRET,
      grant_type = "client_credentials"
    }),
  })

  local body = assert.res_status(200, res)
  assert.not_nil(body)
  body = cjson.decode(body)
  assert.is_string(body.access_token)
  keycloak_client:close()

  return body.access_token
end


local function request_uri(uri, opts)
  return require("resty.http").new():request_uri(uri, opts)
end

for _, strategy in helpers.all_strategies() do
for _, mtls_plugin  in ipairs({"tls-handshake-modifier", "mtls-auth"}) do
for _, auth_method in ipairs({ "bearer", "introspection" }) do

  describe("proof of possession (mtls) strategy: #" .. strategy .. " auth_method: #" .. auth_method .. " mtls plugin: #" .. mtls_plugin, function()
    local upstream
    local clients
    local JWT

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "ca_certificates",
        "plugins",
      }, {
        mtls_plugin,
        PLUGIN_NAME,
      })

      upstream = http_mock.new(UPSTREAM_PORT)
      upstream:start()

      local service = assert(bp.services:insert {
        name = "mock-service",
        port = UPSTREAM_PORT,
        host = "localhost",
      })
      local route = assert(bp.routes:insert {
        service = service,
        paths   = { "/" },
      })

      if mtls_plugin == "mtls-auth" then
        local root_ca_cert = assert(bp.ca_certificates:insert({
          cert = ROOT_CA_CERT,
        }))

        local intermediate_ca_cert = assert(bp.ca_certificates:insert({
          cert = INTERMEDIATE_CA_CERT,
        }))

        assert(bp.plugins:insert {
          route = route,
          name = "mtls-auth",
          config = {
            ca_certificates = {
              root_ca_cert.id,
              intermediate_ca_cert.id,
            },
            skip_consumer_lookup = true,
          }
        })
      else
        assert(bp.plugins:insert {
          route = route,
          name = "tls-handshake-modifier",
        })
      end
      -- workaround for validation. The table is created when spec.helpers is
      -- loaded, before we can use the helpers.get_db_utils to tell what
      -- plugins are installed
      kong.configuration.loaded_plugins[mtls_plugin] = true
      assert(bp.plugins:insert {
        route  = route,
        name   = PLUGIN_NAME,
        config = {
          issuer                     = ISSUER_SSL_URL,
          client_id                  = {
            KONG_CLIENT_ID,
          },
          client_secret              = {
            KONG_CLIENT_SECRET,
          },
          proof_of_possession_mtls = "strict",
          auth_methods = { auth_method, "session" },
        },
      })
      assert(helpers.start_kong({
        database = strategy,
        plugins = "bundled," .. mtls_plugin .. "," .. PLUGIN_NAME,
        proxy_listen = "0.0.0.0:" .. PROXY_PORT_HTTPS .. " http2 ssl",
        lua_ssl_trusted_certificate = mtls_plugin == "mtls-auth" and
          CERT_ROOT_FOLDER .. "root_ca.crt," ..
          CERT_ROOT_FOLDER .. "intermediate_ca.crt" or nil,
      }))

      clients = {}
      clients.valid_client = helpers.http_client({
        scheme = "https",
        host = "127.0.0.1",
        port = PROXY_PORT_HTTPS,
        ssl_verify = false,
        ssl_client_cert = USER_CERT,
        ssl_client_priv_key = USER_KEY,
      })
      clients.valid_client_2 = helpers.http_client({
        scheme = "https",
        host = "127.0.0.1",
        port = PROXY_PORT_HTTPS,
        ssl_verify = false,
        ssl_client_cert = USER_CERT_2,
        ssl_client_priv_key = USER_KEY_2,
      })
      -- malicious users without a valid cert (should not be able to access)
      clients.malicious_client_1 = helpers.http_client({
        scheme = "https",
        host = "127.0.0.1",
        port = PROXY_PORT_HTTPS,
        ssl_verify = false,
      })

      clients.malicious_client_2 = helpers.http_client({
        scheme = "https",
        host = "127.0.0.1",
        port = PROXY_PORT_HTTPS,
        ssl_verify = false,
        ssl_client_cert = RANDOM_SSL_CLIENT_CERT,
        ssl_client_priv_key = RANDOM_SSL_CLIENT_PRIV_KEY,
      })

      JWT = get_jwt_from_token_endpoint()
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
      upstream:stop()
      for _, client in pairs(clients) do
        client:close()
      end
    end)

    for _, test_client in ipairs{"valid_client", "valid_client_2", "malicious_client_1", "malicious_client_2"} do
      it("Cert chain works with " .. test_client, function()
        local res = assert(clients[test_client]:send {
          path = "/",
          headers = {
            Authorization = "Bearer " .. JWT,
          }
        })

        if test_client == "valid_client" then
          assert.res_status(200, res)
        else
          assert.res_status(401, res)
          if mtls_plugin ~= "mtls-auth" or test_client == "valid_client_2" then
            -- the other clients are blocked during the initial handshake if `mtls-auth` is configured
            assert.matches("invalid_token", res.headers["WWW-Authenticate"])
          end
        end
      end)

      it("validates token possession when `session` auth_method is used by #" .. test_client, function()
        -- session initialization with a valid token by `valid_client`
        local res = assert(clients.valid_client:send {
          path = "/",
          headers = {
            Authorization = "Bearer " .. JWT,
          }
        })
        assert.res_status(200, res)

        local cookies = res.headers["set-cookie"]
        local user_session_header_table = {}
        if type(cookies) == "table" then
          -- multiple cookies can be expected
          for i, cookie in ipairs(cookies) do
            user_session_header_table[i] = string.sub(cookie, 0, string.find(cookie, ";") -1)
          end
        else
            user_session_header_table[1] = string.sub(cookies, 0, string.find(cookies, ";") -1)
        end

        -- clients use the valid session to access the protected resource
        res = assert(clients[test_client]:send {
          path = "/",
          headers = {
            Cookie = user_session_header_table
          }
        })

        -- only the valid client should be able to access
        if test_client == "valid_client" then
          assert.res_status(200, res)

        else
          assert.res_status(401, res)

          -- the other clients are blocked during the initial handshake if `mtls-auth` is configured
          if mtls_plugin ~= "mtls-auth" or test_client == "valid_client_2" then
            assert.matches("invalid_token", res.headers["WWW-Authenticate"])
          end
        end
      end)
    end
  end)
end
end


describe("mTLS Client Authentication strategy: #" .. strategy, function()
  local valid_cert_id   = "28a3ec7a-3fe0-4b85-909b-8c42c59f3ebf"
  local invalid_cert_id = "60450682-f39f-4848-897b-6d6133b45de4"
  local expired_cert_id = "7c29c59a-0d16-48f2-8806-b95f29c07d4e"

  local valid_cert_path   = CERT_ROOT_FOLDER .. "client-cert.pem"
  local valid_key_path    = CERT_ROOT_FOLDER .. "client-key.pem"
  local invalid_cert_path = CERT_ROOT_FOLDER .. "hacker-cert.pem"
  local invalid_key_path  = CERT_ROOT_FOLDER .. "hacker-key.pem"
  local expired_cert_path = CERT_ROOT_FOLDER .. "expired-cert.pem"
  local expired_key_path  = CERT_ROOT_FOLDER .. "expired-key.pem"

  local VALID_CERT_STR   = pl_file.read(valid_cert_path)
  local VALID_KEY_STR    = pl_file.read(valid_key_path)
  local INVALID_CERT_STR = pl_file.read(invalid_cert_path)
  local INVALID_KEY_STR  = pl_file.read(invalid_key_path)
  local EXPIRED_CERT_STR = pl_file.read(expired_cert_path)
  local EXPIRED_KEY_STR  = pl_file.read(expired_key_path)

  local function set_up_plugin_start_kong(configs, kong_config)
    local bp = helpers.get_db_utils(strategy, {
      "routes",
      "services",
      "ca_certificates",
      "plugins",
    }, {
      PLUGIN_NAME,
    })

    local service = assert(bp.services:insert {
      name = "mock-service",
      host = "localhost",
    })

    bp.routes:insert {
      service = service,
      paths   = { "/logout" },
    }

    bp.certificates:insert {
      cert = VALID_CERT_STR,
      key = VALID_KEY_STR,
      id = valid_cert_id,
    }

    bp.certificates:insert {
      cert = INVALID_CERT_STR,
      key = INVALID_KEY_STR,
      id = invalid_cert_id,
    }

    bp.certificates:insert {
      cert = EXPIRED_CERT_STR,
      key = EXPIRED_KEY_STR,
      id = expired_cert_id,
    }


    for path, plugin_config in pairs(configs) do
      local route = assert(bp.routes:insert {
        service = service,
        paths   = { path },
      })

      assert(bp.plugins:insert {
        route  = route,
        name   = PLUGIN_NAME,
        config = plugin_config,
      })
    end

    assert(helpers.start_kong(tablex.merge({
      database = strategy,
      plugins = "bundled," .. PLUGIN_NAME,
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }, kong_config or {}, true)))
  end


  local function get_tokens(proxy_client, path, token_key)
    local token, inv_token

    local res = proxy_client:get(path, {
      headers = {
        Authorization = PASSWORD_CREDENTIALS,
      },
    })
    assert.response(res).has.status(200)
    local json = assert.response(res).has.jsonbody()
    token = json.headers[token_key]

    if token_key == "authorization" then
      assert.equal("Bearer", string.sub(token, 1, 6))
      token = string.sub(token, 8)
    end

    if string.sub(token, -4) == "7oig" then
      inv_token = string.sub(token, 1, -5) .. "cYe8"
    else
      inv_token = string.sub(token, 1, -5) .. "7oig"
    end

    return token, inv_token
  end


  ------------------------------------------------------
  -- Token Endpoint
  ------------------------------------------------------
  describe("Authorization code flow", function()
    local proxy_client

    local valid_path = "/auth-code-valid"
    local invalid_path = "/auth-code-invalid"

    local plugin_config_auth_code = {
      issuer = ISSUER_SSL_URL,
      client_id = {
        TLS_AUTH_CLIENT_ID
      },
      scopes = {
        -- this is the default
        "openid",
      },
      auth_methods = {
        "authorization_code"
      },
      preserve_query_args = true,
      login_action = "upstream",
      login_tokens = {},
      client_auth = { "tls_client_auth" },
      upstream_refresh_token_header = "refresh_token",
      refresh_token_param_name = "refresh_token",
    }

    local function do_auth_code_flow(path)
      local res = proxy_client:get(path, {
        headers = {
          ["Host"] = KONG_HOSTNAME
        }
      })
      assert.response(res).has.status(302)
      local redirect = res.headers["Location"]
      local auth_cookie = res.headers["Set-Cookie"]
      local auth_cookie_cleaned = string.sub(auth_cookie, 0, string.find(auth_cookie, ";") -1)
      local rres, err = request_uri(redirect, {
        headers = {
          ["User-Agent"] = USER_AGENT,
          ["Host"] = KEYCLOAK_HOST .. ":" .. KEYCLOAK_SSL_PORT,
        },
        ssl_verify = false,
      })
      assert.is_nil(err)
      assert.equal(200, rres.status)

      local cookies = rres.headers["Set-Cookie"]
      local user_session
      local user_session_header_table = {}
      for _, cookie in ipairs(cookies) do
        user_session = string.sub(cookie, 0, string.find(cookie, ";") -1)
        if string.find(user_session, 'AUTH_SESSION_ID=', 1, true) ~= 1 then
          -- auth_session_id is dropped by the browser for non-https connections
          table.insert(user_session_header_table, user_session)
        end
      end
      -- get the action_url from submit button and post username:password
      local action_start = string.find(rres.body, 'action="', 0, true)
      local action_end = string.find(rres.body, '"', action_start+8, true)
      local login_button_url = string.sub(rres.body, action_start+8, action_end-1)
      -- the login_button_url is endcoded. decode it
      login_button_url = string.gsub(login_button_url,"&amp;", "&")
      -- build form_data
      local form_data = "username="..USERNAME.."&password="..PASSWORD.."&credentialId="
      local opts = { method = "POST",
        body = form_data,
        ssl_verify = false,
        headers = {
          ["User-Agent"] = USER_AGENT,
          ["Host"] = KEYCLOAK_HOST .. ":" .. KEYCLOAK_SSL_PORT,
          ["Content-Type"] = "application/x-www-form-urlencoded",
          Cookie = user_session_header_table,
      }}
      local loginres
      loginres, err = request_uri(login_button_url, opts)
      assert.is_nil(err)
      assert.equal(302, loginres.status)

      -- after sending login data to the login action page, expect a redirect
      local upstream_url = loginres.headers["Location"]
      local ures
      ures, err = request_uri(upstream_url, {
        headers = {
          -- authenticate using the cookie from the initial request
          Cookie = auth_cookie_cleaned
        },
        ssl_verify = false,
      })

      return ures, err
    end

    lazy_setup(function()
      local plugin_config_valid_cert = tablex.merge(plugin_config_auth_code, {
        tls_client_auth_cert_id = valid_cert_id,
      }, true)
      local plugin_config_invalid_cert = tablex.merge(plugin_config_auth_code, {
        tls_client_auth_cert_id = invalid_cert_id,
      }, true)

      set_up_plugin_start_kong({
        [valid_path] = plugin_config_valid_cert,
        [invalid_path] = plugin_config_invalid_cert,
      }, {
        lua_ssl_trusted_certificate = CERT_ROOT_FOLDER .. "root_ca.crt," ..
                                      CERT_ROOT_FOLDER .. "intermediate_ca.crt",
        lua_ssl_verify_depth = 2,
      })

      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end
      helpers.stop_kong(nil, true)
    end)

    it("Authorizes a valid client certificate", function()
      local ures, err = do_auth_code_flow(valid_path)

      assert.is_nil(err)
      assert.equal(200, ures.status)

      local json = assert(cjson.decode(ures.body))
      assert.is_not_nil(json.headers.authorization)
      assert.equal("Bearer", string.sub(json.headers.authorization, 1, 6))
    end)

    it("Rejects an invalid client certificate", function()
      local ures, err = do_auth_code_flow(invalid_path)

      assert.is_nil(err)
      assert.equal(401, ures.status)
    end)
  end)

  describe("Password Grant", function()
    local proxy_client

    local valid_path = "/password-grant-valid"
    local invalid_path = "/password-grant-invalid"

    local plugin_config_password_grant = {
      issuer = ISSUER_SSL_URL,
      scopes = {
        -- this is the default
        "openid",
      },
      client_id = {
        TLS_AUTH_CLIENT_ID,
      },
      upstream_refresh_token_header = "refresh_token",
      refresh_token_param_name      = "refresh_token",
      auth_methods = {
        "password",
      },
      display_errors = true,
      client_auth = { "tls_client_auth" },
    }

    lazy_setup(function()
      local plugin_config_valid_cert = tablex.merge(plugin_config_password_grant, {
        tls_client_auth_cert_id = valid_cert_id,
      }, true)
      local plugin_config_invalid_cert = tablex.merge(plugin_config_password_grant, {
        tls_client_auth_cert_id = invalid_cert_id,
      }, true)

      set_up_plugin_start_kong({
        [valid_path] = plugin_config_valid_cert,
        [invalid_path] = plugin_config_invalid_cert,
      }, {
        lua_ssl_trusted_certificate = CERT_ROOT_FOLDER .. "root_ca.crt," ..
                                      CERT_ROOT_FOLDER .. "intermediate_ca.crt",
        lua_ssl_verify_depth = 2,
      })

      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end
      helpers.stop_kong(nil, true)
    end)

    it("Authorizes a valid client certificate", function()
      local res = proxy_client:get(valid_path, {
        headers = {
          Authorization = PASSWORD_CREDENTIALS,
        },
      })

      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.not_nil(json.headers.authorization)
      assert.equals("Bearer", string.sub(json.headers.authorization, 1, 6))
    end)

    it("Rejects an invalid client certificate", function()
      local res = proxy_client:get(invalid_path, {
        headers = {
          Authorization = PASSWORD_CREDENTIALS,
        },
      })

      assert.response(res).has.status(401)
    end)
  end)

  describe("Refresh Token Grant", function()
    local proxy_client, valid_token, invalid_token

    local valid_path = "/refresh-token-valid"
    local invalid_path = "/refresh-token-invalid"

    local plugin_config_ref_token = {
      issuer = ISSUER_SSL_URL,
      scopes = { "openid" },
      client_id = { TLS_AUTH_CLIENT_ID },
      upstream_refresh_token_header = "refresh_token",
      refresh_token_param_name      = "refresh_token",
      auth_methods = {
        "refresh_token",
        "password",
      },
      client_auth = { "tls_client_auth" },
    }

    lazy_setup(function()
      local plugin_config_valid_cert = tablex.merge(plugin_config_ref_token, {
        tls_client_auth_cert_id = valid_cert_id,
      }, true)
      local plugin_config_invalid_cert = tablex.merge(plugin_config_ref_token, {
        tls_client_auth_cert_id = invalid_cert_id,
      }, true)

      set_up_plugin_start_kong({
        [valid_path] = plugin_config_valid_cert,
        [invalid_path] = plugin_config_invalid_cert,
      }, {
        lua_ssl_trusted_certificate = CERT_ROOT_FOLDER .. "root_ca.crt," ..
                                      CERT_ROOT_FOLDER .. "intermediate_ca.crt",
        lua_ssl_verify_depth = 2,
      })

      proxy_client = helpers.proxy_client()
      valid_token, invalid_token = get_tokens(proxy_client, valid_path, "refresh_token")
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end
      helpers.stop_kong(nil, true)
    end)

    it("Authorizes a valid client certificate with valid token", function()
      local res = proxy_client:get(valid_path, {
        headers = {
          ["Refresh-Token"] = valid_token,
        },
      })

      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.is_not_nil(json.headers.authorization)
      assert.equal("Bearer", string.sub(json.headers.authorization, 1, 6))
      assert.is_not_nil(json.headers.refresh_token)
      assert.not_equal(valid_token, json.headers.refresh_token)
    end)

    it("Rejects a valid client certificate with an invalid token", function()
      local res = proxy_client:get(valid_path, {
        headers = {
          ["Refresh-Token"] = invalid_token,
        },
      })

      assert.response(res).has.status(401)
      local json = assert.response(res).has.jsonbody()
      assert.same("Unauthorized", json.message)
      local header = res.headers["WWW-Authenticate"]
      assert.matches(string.format('error="invalid_token"'), header)
    end)

    it("Rejects invalid client certificate with valid token", function()
      local res = proxy_client:get(invalid_path, {
        headers = {
          ["Refresh-Token"] = valid_token,
        },
      })

      assert.response(res).has.status(401)
      local json = assert.response(res).has.jsonbody()
      assert.same("Unauthorized", json.message)
      local header = res.headers["WWW-Authenticate"]
      assert.matches(string.format('error="invalid_token"'), header)
    end)
  end)


  ------------------------------------------------------
  -- Introspection Endpoint
  ------------------------------------------------------
  describe("Introspection Authentication", function()
    local proxy_client, valid_token, invalid_token

    local valid_path = "/introspection-valid"
    local invalid_path = "/introspection-invalid"

    local plugin_config_introspection = {
      issuer = ISSUER_SSL_URL,
      scopes = { "openid" },
      client_id = { TLS_AUTH_CLIENT_ID },
      auth_methods = { "introspection" },
      bearer_token_param_type = { "body" },
      cache_introspection = false,
      client_auth = { "tls_client_auth" },
    }

    lazy_setup(function()
      local plugin_config_valid_cert = tablex.merge(plugin_config_introspection, {
        tls_client_auth_cert_id = valid_cert_id,
      }, true)
      local plugin_config_invalid_cert = tablex.merge(plugin_config_introspection, {
        tls_client_auth_cert_id = invalid_cert_id,
      }, true)

      set_up_plugin_start_kong({
        [valid_path] = plugin_config_valid_cert,
        [invalid_path] = plugin_config_invalid_cert,
        ["/tokens"] = {
          issuer = ISSUER_SSL_URL,
          scopes = {
            "openid",
          },
          client_id = {
            TLS_AUTH_CLIENT_ID,
          },
          client_auth = { "tls_client_auth" },
          cache_introspection = false,
          tls_client_auth_cert_id = valid_cert_id,
        },
      }, {
        lua_ssl_trusted_certificate = CERT_ROOT_FOLDER .. "root_ca.crt," ..
                                      CERT_ROOT_FOLDER .. "intermediate_ca.crt",
        lua_ssl_verify_depth = 2,
      })

      proxy_client = helpers.proxy_client()
      valid_token, invalid_token = get_tokens(proxy_client, "/tokens", "authorization")
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end
      helpers.stop_kong(nil, true)
    end)

    it("Authorizes a valid client certificate with valid token", function()
      local res = proxy_client:get(valid_path, {
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
        },
        body = ngx.encode_args({
          access_token = valid_token,
        }),
      })

      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.not_nil(json.headers.authorization)
      assert.equal(valid_token, string.sub(json.headers.authorization, 8))
    end)

    it("Rejects a valid client certificate with invalid token", function()
      local res = proxy_client:get(valid_path, {
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
        },
        body = ngx.encode_args({
          access_token = invalid_token,
        }),
      })

      assert.response(res).has.status(401)
    end)

    it("Rejects invalid client certificate with valid token", function()
      local res = proxy_client:get(invalid_path, {
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
        },
        body = ngx.encode_args({
          access_token = valid_token,
        }),
      })

      assert.response(res).has.status(401)
    end)
  end)


  ------------------------------------------------------
  -- Token Revocation Endpoint
  ------------------------------------------------------
  describe("Revocation", function()
    local proxy_client
    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, {
        PLUGIN_NAME
      })

      local service = bp.services:insert {
        name = PLUGIN_NAME,
        path = "/anything"
      }
      local route = bp.routes:insert {
        service = service,
        paths   = { "/" },
      }

      local c = bp.certificates:insert {
        cert = VALID_CERT_STR,
        key = VALID_KEY_STR,
      }
      valid_cert_id = c.id

      bp.plugins:insert {
        route   = route,
        name    = PLUGIN_NAME,
        config  = {
          issuer    = ISSUER_SSL_URL,
          client_id = { TLS_AUTH_CLIENT_ID },
          auth_methods = {
            "session",
            "password"
          },
          logout_uri_suffix = "/logout",
          logout_methods = {
            "POST",
          },
          logout_revoke = true,
          display_errors = true,
          client_auth = { "tls_client_auth" },
          tls_client_auth_cert_id = valid_cert_id,
        },
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins    = "bundled," .. PLUGIN_NAME,
        lua_ssl_trusted_certificate = CERT_ROOT_FOLDER .. "root_ca.crt," ..
                                      CERT_ROOT_FOLDER .. "intermediate_ca.crt",
        lua_ssl_verify_depth = 2,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    describe("logout", function ()

      local user_session
      local user_session_header_table = {}
      local user_token

      lazy_setup(function()
        local client = helpers.proxy_client()
        local res = client:get("/", {
          headers = {
            Authorization = PASSWORD_CREDENTIALS,
          },
        })
        assert.response(res).has.status(200)

        local json = assert.response(res).has.jsonbody()
        local cookies = res.headers["Set-Cookie"]
        if type(cookies) == "table" then
          -- multiple cookies can be expected
          for i, cookie in ipairs(cookies) do
            user_session = string.sub(cookie, 0, string.find(cookie, ";") -1)
            user_session_header_table[i] = user_session
          end
        else
            user_session = string.sub(cookies, 0, string.find(cookies, ";") -1)
            user_session_header_table[1] = user_session
        end
        user_token = string.sub(json.headers.authorization, 8, -1)
      end)

      it("successfully revokes token", function ()
        local res = proxy_client:get("/", {
          headers = {
            Cookie = user_session_header_table
          },
        })

        -- Test that the session auth works
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.equal(user_token, string.sub(json.headers.authorization, 8))
        -- logout
        local lres = proxy_client:post("/logout?query-args-wont-matter=1", {
          headers = {
            Cookie = user_session_header_table,
          },
        })
        assert.response(lres).has.status(302)
        -- test if Expires=beginningofepoch
        local cookie = lres.headers["Set-Cookie"]
        local expected_header_name = "Expires="
        -- match from Expires= until next ; divider
        local expiry_init = string.find(cookie, expected_header_name)
        local expiry_date = string.sub(cookie, expiry_init + #expected_header_name, string.find(cookie, ';', expiry_init)-1)
        assert(expiry_date, "Thu, 01 Jan 1970 00:00:01 GMT")
        -- follow redirect (call IDP)

        local redirect = lres.headers["Location"]
        local rres, err = request_uri(redirect, {
          ssl_verify = false,
        })
        assert.is_nil(err)
        assert.equal(200, rres.status)
      end)
    end)
  end)


  ------------------------------------------------------
  -- Other tests
  ------------------------------------------------------
  describe("Expired Certificate", function()
    local proxy_client

    local path = "/password-grant-exp"

    local plugin_config_password_grant = {
      issuer = ISSUER_SSL_URL,
      scopes = {
        -- this is the default
        "openid",
      },
      client_id = {
        TLS_AUTH_CLIENT_ID,
      },
      upstream_refresh_token_header = "refresh_token",
      refresh_token_param_name      = "refresh_token",
      auth_methods = {
        "password",
      },
      client_auth = { "tls_client_auth" },
      tls_client_auth_cert_id = expired_cert_id,
      display_errors = true,
    }

    lazy_setup(function()
      set_up_plugin_start_kong({
        [path] = plugin_config_password_grant,
      }, {
        lua_ssl_trusted_certificate = CERT_ROOT_FOLDER .. "root_ca.crt," ..
                                      CERT_ROOT_FOLDER .. "intermediate_ca.crt",
        lua_ssl_verify_depth = 2,
      })

      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end
      helpers.stop_kong(nil, true)
    end)

    it("notifies in the logs", function()
      proxy_client:get(path, {
        headers = {
          Authorization = PASSWORD_CREDENTIALS,
        },
      })

      -- looks like keycloak allows using expired client certs
      -- so we are not expecting a 401 here
      assert.logfile().has.line("tls_client_auth_cert expired at")
    end)
  end)


  describe("With tls_client_auth_ssl_verify = false", function()
    local proxy_client

    local valid_path = "/password-grant-valid"

    local plugin_config_password_grant = {
      issuer = ISSUER_SSL_URL,
      scopes = {
        -- this is the default
        "openid",
      },
      client_id = {
        TLS_AUTH_CLIENT_ID,
      },
      upstream_refresh_token_header = "refresh_token",
      refresh_token_param_name      = "refresh_token",
      auth_methods = {
        "password",
      },
      display_errors = true,
      client_auth = { "tls_client_auth" },
      tls_client_auth_ssl_verify = false,
    }

    lazy_setup(function()
      local plugin_config_valid_cert = tablex.merge(plugin_config_password_grant, {
        tls_client_auth_cert_id = valid_cert_id,
      }, true)

      -- start kong without the lua_ssl_trusted_certificate setting
      set_up_plugin_start_kong({
        [valid_path] = plugin_config_valid_cert,
      })

      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end
      helpers.stop_kong(nil, true)
    end)

    it("Authorizes a valid client certificate", function()
      local res = proxy_client:get(valid_path, {
        headers = {
          Authorization = PASSWORD_CREDENTIALS,
        },
      })

      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.not_nil(json.headers.authorization)
      assert.equals("Bearer", string.sub(json.headers.authorization, 1, 6))
    end)
  end)
end)
end
