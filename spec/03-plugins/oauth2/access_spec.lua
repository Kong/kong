local helpers = require "spec.helpers"
local cjson = require "cjson"
local meta = require "kong.meta"
local pl_stringx = require "pl.stringx"

describe("Plugin: oauth2", function()
  local client
  setup(function()
    helpers.dao:truncate_tables()
    helpers.execute "pkill nginx; pkill serf; pkill dnsmasq"
    assert(helpers.prepare_prefix())

    local consumer = assert(helpers.dao.consumers:insert {
      username = "bob"
    })
    assert(helpers.dao.oauth2_credentials:insert {
      client_id = "clientid123",
      client_secret = "secret123",
      redirect_uri = "http://google.com/kong",
      name = "testapp",
      consumer_id = consumer.id
    })
    assert(helpers.dao.oauth2_credentials:insert {
      client_id = "clientid789",
      client_secret = "secret789",
      redirect_uri = "http://google.com/kong?foo=bar&code=123",
      name = "testapp2",
      consumer_id = consumer.id
    })

    local api1 = assert(helpers.dao.apis:insert {
      request_host = "oauth2.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "oauth2",
      api_id = api1.id,
      config = { 
        scopes = { "email", "profile", "user.email" }, 
        mandatory_scope = true, 
        provision_key = "provision123", 
        token_expiration = 5, 
        enable_implicit_grant = true 
      }
    })

    local api2 = assert(helpers.dao.apis:insert {
      request_host = "mockbin-path.com",
      request_path = "/somepath/",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "oauth2",
      api_id = api2.id,
      config = { 
        scopes = { "email", "profile" }, 
        mandatory_scope = true, 
        provision_key = "provision123", 
        token_expiration = 5, 
        enable_implicit_grant = true
      }
    })

    local api3 = assert(helpers.dao.apis:insert {
      request_host = "oauth2_3.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "oauth2",
      api_id = api3.id,
      config = { 
        scopes = { "email", "profile" }, 
        mandatory_scope = true, 
        provision_key = "provision123", 
        token_expiration = 5, 
        enable_implicit_grant = true, 
        hide_credentials = true 
      }
    })

    local api4 = assert(helpers.dao.apis:insert {
      request_host = "oauth2_4.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "oauth2",
      api_id = api4.id,
      config = {
        scopes = { "email", "profile" }, 
        mandatory_scope = true, 
        provision_key = "provision123", 
        token_expiration = 5, 
        enable_client_credentials = true, 
        enable_authorization_code = false 
      }
    })

    local api5 = assert(helpers.dao.apis:insert {
      request_host = "oauth2_5.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "oauth2",
      api_id = api5.id,
      config = { 
        scopes = { "email", "profile" }, 
        mandatory_scope = true, 
        provision_key = "provision123", 
        token_expiration = 5, 
        enable_password_grant = true, 
        enable_authorization_code = false 
      }
    })

    local api6 = assert(helpers.dao.apis:insert {
      request_host = "oauth2_6.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "oauth2",
      api_id = api6.id,
      config = { 
        scopes = { "email", "profile", "user.email" }, 
        mandatory_scope = true, 
        provision_key = "provision123", 
        token_expiration = 5, 
        enable_implicit_grant = true, 
        accept_http_if_already_terminated = true 
      }
    })

    assert(helpers.start_kong())
    proxy_client = assert(helpers.http_client("127.0.0.1", pl_stringx.split(helpers.test_conf.proxy_listen_ssl, ":")[2]))
    proxy_client:ssl_handshake()
  end)
  teardown(function()
    if client then
      client:close()
    end
    helpers.stop_kong()
    --helpers.clean_prefix()
  end)

  local function provision_code()
    local res = assert(proxy_client:send {
      method = "POST",
      path = "/oauth2/authorize",
      body = {
        provision_key = "provision123",
        client_id = "client123", 
        scope = "email", 
        response_type = "code", 
        state = "hello", 
        authenticated_userid = "userid123"
      },
      headers = {
        ["Host"] = "oauth2.com",
        ["Content-Type"] = "application/json"
      }
    })
    local body = cjson.decode(res:read_body())
    if body.redirect_uri then
      local iterator, err = ngx.re.gmatch(body.redirect_uri, "^http://google\\.com/kong\\?code=([\\w]{32,32})&state=hello$")
      assert.is_nil(err)
      local m, err = iterator()
      assert.is_nil(err)
      return m[1]
    end
  end

  local function provision_token()
    local code = provision_code()
    local res = assert(proxy_client:send {
      method = "POST",
      path = "/oauth2/token",
      body = { code = code, client_id = "clientid123", client_secret = "secret123", grant_type = "authorization_code" },
      headers = {
        ["Host"] = "oauth2.com",
        ["Content-Type"] = "application/json"
      }
    })
    local token = cjson.decode(assert.res_status(200, res))
    assert.is_table(token)
    return token
  end

  describe("OAuth2 Authorization", function()
    describe("Code Grant", function()
      it("returns an error when no provision_key is being sent", function()

      end)
      it("returns an error when no parameter is being sent", function()

      end)
      it("returns an error when only provision_key and authenticated_userid are sent", function()

      end)
      it("returns an error when only the client_is being sent", function()

      end)
      it("returns an error when only the client_is being sent", function()

      end)
      it("returns an error when no response_type is being sent", function()

      end)
      it("returns an error with a state when no response_type is being sent", function()

      end)
      it("returns error when the redirect_uri does not match", function()

      end)
      it("works even if redirect_uri contains a query string", function()

      end)
      it("fails when not under HTTPS", function()

      end)
      it("works when not under HTTPS but accept_http_if_already_terminated is true", function()

      end)
      it("fails when not under HTTPS and accept_http_if_already_terminated is false", function()

      end)
      it("returns success", function()

      end)
      it("fails with a path when using the DNS", function()

      end)
      it("returns success with a path", function()

      end)
      it("should return success when requesting the url with final slash", function()

      end)
      it("should return success with a state", function()

      end)
      it("returns success and store authenticated user properties", function()

      end)
      it("should return success with a dotted scope and store authenticated user properties", function()

      end)
    end)

    describe("Implicit Grant", function()
      it("should return success", function()

      end)
      it("should return success and the state", function()

      end)
      it("should return success and the token should have the right expiration", function()

      end)
      it("should return success and store authenticated user properties", function()

      end)
      it("should return set the right upstream headers", function()

      end)
    end)

    describe("Client Credentials", function()
      it("should return an error when client_secret is not sent", function()

      end)
      it("should return an error when client_secret is not sent", function()

      end)
      it("should fail when not under HTTPS", function()

      end)
      it("should return fail when setting authenticated_userid and no provision_key", function()

      end)
      it("should return fail when setting authenticated_userid and invalid provision_key", function()

      end)
      it("should return success", function()

      end)
      it("should return success with authenticated_userid and valid provision_key", function()

      end)
      it("should return success with authorization header", function()

      end)
      it("should return an error with a wrong authorization header", function()

      end)
      it("should return set the right upstream headers", function()

      end)
      it("should return set the right upstream headers", function()

      end)
    end)

    describe("Password Grant", function()
      it("should block unauthorized requests", function()

      end)
      it("should return an error when client_secret is not sent", function()

      end)
      it("should return an error when client_secret is not sent", function()

      end)
      it("should fail when no provision key is being sent", function()

      end)
      it("should fail when no provision key is being sent", function()

      end)
      it("should fail when no authenticated user id is being sent", function()

      end)
      it("should fail when no authenticated user id is being sent", function()

      end)
      it("should fail when no authenticated user id is being sent", function()

      end)
      it("should return an error with a wrong authorization header", function()

      end)
      it("should return an error with a wrong authorization header", function()

      end)
    end)
  end)

  describe("OAuth2 Access Token", function()
    it("should return an error when nothing is being sent", function()

    end)
    it("should return an error when only the code is being sent", function()

    end)
    it("should return an error when only the code and client_secret are being sent", function()

    end)
    it("should return an error when only the code and client_secret and client_id are being sent", function()

    end)
    it("should return an error when only the code and client_secret and client_id are being sent", function()

    end)
    it("should return success without state", function()

    end)
    it("should return success with state", function()

    end)
    it("should return set the right upstream headers", function()

    end)
  end)

  describe("Making a request", function()
    it("should work when a correct access_token is being sent in the querystring", function()

    end)
    it("should work when a correct access_token is being sent in a form body", function()

    end)
    it("should work when a correct access_token is being sent in an authorization header (bearer)", function()

    end)
    it("should work when a correct access_token is being sent in an authorization header (token)", function()

    end)
  end)

  describe("Authentication challenge", function()
    it("should return 401 Unauthorized without error if it lacks any authentication information", function()

    end)
    it("should return 401 Unauthorized when an invalid access token is being sent via url parameter", function()

    end)
    it("should return 401 Unauthorized when an invalid access token is being sent via the Authorization header", function()

    end)
    it("should return 401 Unauthorized when token has expired", function()

    end)
  end)

  describe("Refresh Token", function()
    it("should not refresh an invalid access token", function()

    end)
    it("should refresh an valid access token", function()

    end)
    it("should expire after 5 seconds", function()

    end)
  end)

  describe("Hide Credentials", function()
    it("should not hide credentials in the body", function()

    end)
    it("should hide credentials in the body", function()

    end)
    it("should hide credentials in the body", function()

    end)
    it("should hide credentials in the querystring", function()

    end)
    it("should hide credentials in the querystring", function()

    end)
    it("should hide credentials in the querystring", function()

    end)
  end)
end)
