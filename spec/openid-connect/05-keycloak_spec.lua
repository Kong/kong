-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local helpers = require "spec.helpers"


local encode_base64 = ngx.encode_base64
local sub = string.sub
local find = string.find


local PLUGIN_NAME = "openid-connect"
local KEYCLOAK_HOST = "keycloak"
local KEYCLOAK_PORT = 8080
local KEYCLOAK_SSL_PORT = 8443
local REALM_PATH = "/auth/realms/demo"
local DISCOVERY_PATH = "/.well-known/openid-configuration"
local ISSUER_URL = "http://" .. KEYCLOAK_HOST .. ":" .. KEYCLOAK_PORT .. REALM_PATH
local ISSUER_SSL_URL = "https://" .. KEYCLOAK_HOST .. ":" .. KEYCLOAK_SSL_PORT .. REALM_PATH

local USERNAME = "john"
local PASSWORD = "doe"
local CLIENT_ID = "service"
local CLIENT_SECRET = "7adf1a21-6b9e-45f5-a033-d0e8f47b1dbc"
local INVALID_ID = "unknown"
local INVALID_SECRET = "soldier"

local INVALID_CREDENTIALS = "Basic " .. encode_base64(INVALID_ID .. ":" .. INVALID_SECRET)
local PASSWORD_CREDENTIALS = "Basic " .. encode_base64(USERNAME .. ":" .. PASSWORD)
local CLIENT_CREDENTIALS = "Basic " .. encode_base64(CLIENT_ID .. ":" .. CLIENT_SECRET)


local KONG_CLIENT_ID = "kong-client-secret"
local KONG_CLIENT_SECRET = "38beb963-2786-42b8-8e14-a5f391b4ba93"


describe(PLUGIN_NAME .. ": (keycloak)", function()
  it("can access openid connect discovery endpoint on demo realm with http", function()
    local client = helpers.http_client(KEYCLOAK_HOST, KEYCLOAK_PORT)
    local res = client:get(REALM_PATH .. DISCOVERY_PATH)
    assert.response(res).has.status(200)
    local json = assert.response(res).has.jsonbody()
    assert.equal(ISSUER_URL, json.issuer)
  end)

  it("can access openid connect discovery endpoint on demo realm with https", function()
    local client = helpers.http_client(KEYCLOAK_HOST, KEYCLOAK_SSL_PORT)
    assert(client:ssl_handshake(nil, nil, false))
    local res = client:get(REALM_PATH .. DISCOVERY_PATH)
    assert.response(res).has.status(200)
    local json = assert.response(res).has.jsonbody()
    assert.equal(ISSUER_SSL_URL, json.issuer)
  end)

  describe("authentication", function()
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils("postgres", {
        "routes",
        "services",
        "plugins",
      }, {
        PLUGIN_NAME
      })

      local service = bp.services:insert {
        name = "openid-connect",
        path = "/anything"
      }

      local route = bp.routes:insert {
        service = service,
        paths   = { "/" },
      }

      bp.plugins:insert {
        route   = route,
        name    = "openid-connect",
        config  = {
          issuer    = ISSUER_URL,
          scopes = {
            "openid",
          },
          client_id = {
            KONG_CLIENT_ID,
          },
          client_secret = {
            KONG_CLIENT_SECRET,
          },
          upstream_refresh_token_header = "refresh_token",
          refresh_token_param_name      = "refresh_token",
        },
      }

      local introspection = bp.routes:insert {
        service = service,
        paths   = { "/introspection" },
      }

      bp.plugins:insert {
        route   = introspection,
        name    = "openid-connect",
        config  = {
          issuer    = ISSUER_URL,
          client_id = {
            KONG_CLIENT_ID,
          },
          client_secret = {
            KONG_CLIENT_SECRET,
          },
          auth_methods = {
            "introspection",
          },
        },
      }

      local userinfo = bp.routes:insert {
        service = service,
        paths   = { "/userinfo" },
      }

      bp.plugins:insert {
        route   = userinfo,
        name    = "openid-connect",
        config  = {
          issuer    = ISSUER_URL,
          client_id = {
            KONG_CLIENT_ID,
          },
          client_secret = {
            KONG_CLIENT_SECRET,
          },
          auth_methods = {
            "userinfo",
          },
        },
      }

      local kong_oauth2 = bp.routes:insert {
        service = service,
        paths   = { "/kong-oauth2" },
      }

      bp.plugins:insert {
        route   = kong_oauth2,
        name    = "openid-connect",
        config  = {
          issuer    = ISSUER_URL,
          client_id = {
            KONG_CLIENT_ID,
          },
          client_secret = {
            KONG_CLIENT_SECRET,
          },
          auth_methods = {
            "kong_oauth2",
          },
        },
      }

      local session = bp.routes:insert {
        service = service,
        paths   = { "/session" },
      }

      bp.plugins:insert {
        route   = session,
        name    = "openid-connect",
        config  = {
          issuer    = ISSUER_URL,
          client_id = {
            KONG_CLIENT_ID,
          },
          client_secret = {
            KONG_CLIENT_SECRET,
          },
          auth_methods = {
            "session",
          },
        },
      }

      local jane = bp.consumers:insert {
        username = "jane",
      }

      bp.oauth2_credentials:insert {
        name          = "demo",
        client_id     = "client",
        client_secret = "secret",
        hash_secret   = true,
        consumer      = jane
      }

       local auth = bp.routes:insert {
        service = ngx.null,
        paths   = { "/auth" },
      }

      bp.plugins:insert {
        route   = auth,
        name    = "oauth2",
        config  = {
          global_credentials        = true,
          enable_client_credentials = true,
        },
      }

      assert(helpers.start_kong({
        database   = "postgres",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins    = "bundled," .. PLUGIN_NAME,
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

    describe("authorization code flow", function()
      it("is initiated without credentials", function()
        local res = proxy_client:get("/")
        assert.response(res).has.status(302)
      end)
    end)

    describe("password grant", function()
      it("is not allowed with invalid credentials", function()
        local res = proxy_client:get("/", {
          headers = {
            Authorization = INVALID_CREDENTIALS,
          },
        })

        assert.response(res).has.status(401)
        local json = assert.response(res).has.jsonbody()
        assert.same("Unauthorized", json.message)
      end)

      it("is not allowed with valid client credentials when grant type is given", function()
        local res = proxy_client:get("/", {
          headers = {
            Authorization = CLIENT_CREDENTIALS,
            ["Grant-Type"] = "password",
          },
        })

        assert.response(res).has.status(401)
        local json = assert.response(res).has.jsonbody()
        assert.same("Unauthorized", json.message)
      end)

      it("is allowed with valid credentials", function()
        local res = proxy_client:get("/", {
          headers = {
            Authorization = PASSWORD_CREDENTIALS,
          },
        })

        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.is_not_nil(json.headers.authorization)
        assert.equal("Bearer", sub(json.headers.authorization, 1, 6))
      end)
    end)

    describe("client credentials grant", function()
      it("is not allowed with invalid credentials", function()
        local res = proxy_client:get("/", {
          headers = {
            Authorization = INVALID_CREDENTIALS,
          },
        })

        assert.response(res).has.status(401)
        local json = assert.response(res).has.jsonbody()
        assert.same("Unauthorized", json.message)
      end)

      it("is not allowed with valid password credentials when grant type is given", function()
        local res = proxy_client:get("/", {
          headers = {
            Authorization = PASSWORD_CREDENTIALS,
            ["Grant-Type"] = "client_credentials",
          },
        })

        assert.response(res).has.status(401)
        local json = assert.response(res).has.jsonbody()
        assert.same("Unauthorized", json.message)
      end)

      it("is allowed with valid credentials", function()
        local res = proxy_client:get("/", {
          headers = {
            Authorization = CLIENT_CREDENTIALS,
          },
        })

        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.is_not_nil(json.headers.authorization)
        assert.equal("Bearer", sub(json.headers.authorization, 1, 6))
      end)
    end)

    describe("jwt access token", function()
      local user_token
      local client_token
      local invalid_token

      lazy_setup(function()
        local client = helpers.proxy_client()
        local res = client:get("/", {
          headers = {
            Authorization = PASSWORD_CREDENTIALS,
          },
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.equal("Bearer", sub(json.headers.authorization, 1, 6))

        user_token = sub(json.headers.authorization, 8)

        if sub(user_token, -4) == "7oig" then
          invalid_token = sub(user_token, 1, -5) .. "cYe8"
        else
          invalid_token = sub(user_token, 1, -5) .. "7oig"
        end

        res = client:get("/", {
          headers = {
            Authorization = CLIENT_CREDENTIALS,
          },
        })
        assert.response(res).has.status(200)
        json = assert.response(res).has.jsonbody()
        assert.equal("Bearer", sub(json.headers.authorization, 1, 6))

        client_token = sub(json.headers.authorization, 8)

        client:close()
      end)

      it("is not allowed with invalid token", function()
        local res = proxy_client:get("/", {
          headers = {
            Authorization = "Bearer " .. invalid_token,
          },
        })

        assert.response(res).has.status(401)
        local json = assert.response(res).has.jsonbody()
        assert.same("Unauthorized", json.message)
      end)

      it("is allowed with valid user token", function()
        local res = proxy_client:get("/", {
          headers = {
            Authorization = "Bearer " .. user_token,
          },
        })

        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.is_not_nil(json.headers.authorization)
        assert.equal(user_token, sub(json.headers.authorization, 8))
      end)

      it("is allowed with valid client token", function()
        local res = proxy_client:get("/", {
          headers = {
            Authorization = "Bearer " .. client_token,
          },
        })

        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.is_not_nil(json.headers.authorization)
        assert.equal(client_token, sub(json.headers.authorization, 8))
      end)
    end)

    describe("refresh token", function()
      local user_token
      local client_token
      local invalid_token

      lazy_setup(function()
        local client = helpers.proxy_client()
        local res = client:get("/", {
          headers = {
            Authorization = PASSWORD_CREDENTIALS,
            ["Grant-Type"] = "password",
          },
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.is_not_nil(json.headers.refresh_token)

        user_token = json.headers.refresh_token

        if sub(user_token, -4) == "7oig" then
          invalid_token = sub(user_token, 1, -5) .. "cYe8"
        else
          invalid_token = sub(user_token, 1, -5) .. "7oig"
        end

        local client = helpers.proxy_client()
        local res = client:get("/", {
          headers = {
            Authorization = CLIENT_CREDENTIALS,
            ["Grant-Type"] = "client_credentials",
          },
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        print(require "inspect"(json))
        assert.is_not_nil(json.headers.refresh_token)

        client_token = json.headers.refresh_token

        client:close()
      end)

      it("is not allowed with invalid token", function()
        local res = proxy_client:get("/", {
          headers = {
            ["Refresh-Token"] = invalid_token,
          },
        })

        assert.response(res).has.status(401)
        local json = assert.response(res).has.jsonbody()
        assert.same("Unauthorized", json.message)
      end)

      it("is allowed with valid user token", function()
        local res = proxy_client:get("/", {
          headers = {
            ["Refresh-Token"] = user_token,
          },
        })

        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.is_not_nil(json.headers.authorization)
        assert.equal("Bearer", sub(json.headers.authorization, 1, 6))
        assert.is_not_nil(json.headers.refresh_token)
        assert.not_equal(user_token, json.headers.refresh_token)
      end)

      it("is allowed with valid client token", function()
        local res = proxy_client:get("/", {
          headers = {
            ["Refresh-Token"] = client_token,
          },
        })

        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.is_not_nil(json.headers.authorization)
        assert.equal("Bearer", sub(json.headers.authorization, 1, 6))
        assert.is_not_nil(json.headers.refresh_token)
        assert.not_equal(client_token, json.headers.refresh_token)
      end)
    end)

    describe("introspection", function()
      local user_token
      local client_token
      local invalid_token

      lazy_setup(function()
        local client = helpers.proxy_client()
        local res = client:get("/", {
          headers = {
            Authorization = PASSWORD_CREDENTIALS,
          },
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.equal("Bearer", sub(json.headers.authorization, 1, 6))

        user_token = sub(json.headers.authorization, 8)

        if sub(user_token, -4) == "7oig" then
          invalid_token = sub(user_token, 1, -5) .. "cYe8"
        else
          invalid_token = sub(user_token, 1, -5) .. "7oig"
        end

        res = client:get("/", {
          headers = {
            Authorization = CLIENT_CREDENTIALS,
          },
        })
        assert.response(res).has.status(200)
        json = assert.response(res).has.jsonbody()
        assert.equal("Bearer", sub(json.headers.authorization, 1, 6))

        client_token = sub(json.headers.authorization, 8)

        client:close()
      end)

      it("is not allowed with invalid token", function()
        local res = proxy_client:get("/introspection", {
          headers = {
            Authorization = "Bearer " .. invalid_token,
          },
        })

        assert.response(res).has.status(401)
        local json = assert.response(res).has.jsonbody()
        assert.same("Unauthorized", json.message)
      end)

      it("is allowed with valid user token", function()
        local res = proxy_client:get("/introspection", {
          headers = {
            Authorization = "Bearer " .. user_token,
          },
        })

        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.is_not_nil(json.headers.authorization)
        assert.equal(user_token, sub(json.headers.authorization, 8))
      end)

      it("is allowed with valid client token", function()
        local res = proxy_client:get("/introspection", {
          headers = {
            Authorization = "Bearer " .. client_token,
          },
        })

        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.is_not_nil(json.headers.authorization)
        assert.equal(client_token, sub(json.headers.authorization, 8))
      end)
    end)

    describe("userinfo", function()
      local user_token
      local client_token
      local invalid_token

      lazy_setup(function()
        local client = helpers.proxy_client()
        local res = client:get("/", {
          headers = {
            Authorization = PASSWORD_CREDENTIALS,
          },
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.equal("Bearer", sub(json.headers.authorization, 1, 6))

        user_token = sub(json.headers.authorization, 8)

        if sub(user_token, -4) == "7oig" then
          invalid_token = sub(user_token, 1, -5) .. "cYe8"
        else
          invalid_token = sub(user_token, 1, -5) .. "7oig"
        end

        res = client:get("/", {
          headers = {
            Authorization = CLIENT_CREDENTIALS,
          },
        })
        assert.response(res).has.status(200)
        json = assert.response(res).has.jsonbody()
        assert.equal("Bearer", sub(json.headers.authorization, 1, 6))

        client_token = sub(json.headers.authorization, 8)

        client:close()
      end)

      it("is not allowed with invalid token", function()
        local res = proxy_client:get("/userinfo", {
          headers = {
            Authorization = "Bearer " .. invalid_token,
          },
        })

        assert.response(res).has.status(401)
        local json = assert.response(res).has.jsonbody()
        assert.same("Unauthorized", json.message)
      end)

      it("is allowed with valid user token", function()
        local res = proxy_client:get("/userinfo", {
          headers = {
            Authorization = "Bearer " .. user_token,
          },
        })

        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.is_not_nil(json.headers.authorization)
        assert.equal(user_token, sub(json.headers.authorization, 8))
      end)

      it("is allowed with valid client token", function()
        local res = proxy_client:get("/userinfo", {
          headers = {
            Authorization = "Bearer " .. client_token,
          },
        })

        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.is_not_nil(json.headers.authorization)
        assert.equal(client_token, sub(json.headers.authorization, 8))
      end)
    end)

    describe("kong oauth2", function()
      local token
      local invalid_token

      lazy_setup(function()
        local client = helpers.proxy_ssl_client()
        local res = client:post("/auth/oauth2/token", {
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
          },
          body = {
            client_id     = "client",
            client_secret = "secret",
            grant_type    = "client_credentials",
          },
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()

        token = json.access_token

        if sub(token, -4) == "7oig" then
          invalid_token = sub(token, 1, -5) .. "cYe8"
        else
          invalid_token = sub(token, 1, -5) .. "7oig"
        end

        client:close()
      end)

      it("is not allowed with invalid token", function()
        local res = proxy_client:get("/kong-oauth2", {
          headers = {
            Authorization = "Bearer " .. invalid_token,
          },
        })

        assert.response(res).has.status(401)
        local json = assert.response(res).has.jsonbody()
        assert.same("Unauthorized", json.message)
      end)

      it("is allowed with valid token", function()
        local res = proxy_client:get("/kong-oauth2", {
          headers = {
            Authorization = "Bearer " .. token,
          },
        })

        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.is_not_nil(json.headers.authorization)
        assert.equal(token, sub(json.headers.authorization, 8))
      end)
    end)

    describe("session", function()
      local user_session
      local client_session
      local invalid_session

      lazy_setup(function()
        local client = helpers.proxy_client()
        local res = client:get("/", {
          headers = {
            Authorization = PASSWORD_CREDENTIALS,
          },
        })
        assert.response(res).has.status(200)
        local cookies = res.headers["Set-Cookie"]
        local cookie
        if type(cookies) == "table" then
          cookie = cookies[1]
        else
          cookie = cookies
        end

        user_session = sub(cookie, 9, find(cookie, ";") -1)

        if sub(user_session, -4) == "7oig" then
          invalid_session = sub(user_session, 1, -5) .. "cYe8"
        else
          invalid_session = sub(user_session, 1, -5) .. "7oig"
        end

        res = client:get("/", {
          headers = {
            Authorization = CLIENT_CREDENTIALS,
          },
        })
        assert.response(res).has.status(200)
        local cookies = res.headers["Set-Cookie"]
        local cookie
        if type(cookies) == "table" then
          cookie = cookies[1]
        else
          cookie = cookies
        end

        client_session = sub(cookie, 9, find(cookie, ";") -1)

        client:close()
      end)

      it("is not allowed with invalid session", function()
        local res = proxy_client:get("/session", {
          headers = {
            Cookie = "session=" .. invalid_session,
          },
        })

        assert.response(res).has.status(401)
        local json = assert.response(res).has.jsonbody()
        assert.same("Unauthorized", json.message)
      end)

      it("is allowed with valid user session", function()
        local res = proxy_client:get("/session", {
          headers = {
            Cookie = "session=" .. user_session,
            --Cookie = "session_2=" .. user_session[2],
            --Cookie = "session_3=" .. user_session[2],
          },
        })

        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.is_not_nil(json.headers.authorization)
        assert.equal(user_token, sub(json.headers.authorization, 8))
      end)

      it("is allowed with valid client session", function()
        local res = proxy_client:get("/session", {
          headers = {
            Cookie = "session=" .. client_session,
          },
        })

        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.is_not_nil(json.headers.authorization)
        assert.equal(client_token, sub(json.headers.authorization, 8))
      end)
    end)
  end)

  describe("authorization", function()
    -- TODO
  end)

  describe("headers", function()
    -- TODO
  end)

  describe("logout", function()
    -- TODO
  end)

  describe("debug", function()
    -- TODO
  end)


end)
