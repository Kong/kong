local cjson = require "cjson"
local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"

local function provision_code(host, extra_headers)
  local request_client = helpers.proxy_ssl_client()
  local res = assert(request_client:send {
    method = "POST",
    path = "/oauth2/authorize",
    body = {
      provision_key = "provision123",
      client_id = "clientid123",
      scope = "email",
      response_type = "code",
      state = "hello",
      authenticated_userid = "userid123"
    },
    headers = utils.table_merge({
      ["Host"] = host or "oauth2.com",
      ["Content-Type"] = "application/json"
    }, extra_headers)
  })
  assert.response(res).has.status(200)
  local body = assert.response(res).has.jsonbody()
  request_client:close()
  if body.redirect_uri then
    local iterator, err = ngx.re.gmatch(body.redirect_uri, "^http://google\\.com/kong\\?code=([\\w]{32,32})&state=hello$")
    assert.is_nil(err)
    local m, err = iterator()
    assert.is_nil(err)
    return m[1]
  end
end

local function provision_token(host, extra_headers)
  local code = provision_code(host, extra_headers)
  local request_client = helpers.proxy_ssl_client()
  local res = assert(request_client:send {
    method = "POST",
    path = "/oauth2/token",
    body = { code = code, client_id = "clientid123", client_secret = "secret123", grant_type = "authorization_code" },
    headers = utils.table_merge({
      ["Host"] = host or "oauth2.com",
      ["Content-Type"] = "application/json"
    }, extra_headers)
  })
  assert.response(res).has.status(200)
  local token = assert.response(res).has.jsonbody()
  assert.is_table(token)
  request_client:close()
  return token
end


describe("#ci Plugin: oauth2 (access)", function()
  local proxy_ssl_client, proxy_client
  local client1
  setup(function()
    local consumer = assert(helpers.dao.consumers:insert {
      username = "bob"
    })
    local anonymous_user = assert(helpers.dao.consumers:insert {
      username = "no-body"
    })
    client1 = assert(helpers.dao.oauth2_credentials:insert {
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
    assert(helpers.dao.oauth2_credentials:insert {
      client_id = "clientid456",
      client_secret = "secret456",
      redirect_uri = {"http://one.com/one/", "http://two.com/two"},
      name = "testapp3",
      consumer_id = consumer.id
    })

    local api1 = assert(helpers.dao.apis:insert {
      name = "api-1",
      hosts = { "oauth2.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "oauth2",
      api_id = api1.id,
      config = {
        scopes = { "email", "profile", "user.email" },
        enable_authorization_code = true,
        mandatory_scope = true,
        provision_key = "provision123",
        token_expiration = 5,
        enable_implicit_grant = true
      }
    })

    local api2 = assert(helpers.dao.apis:insert {
      name = "api-2",
      hosts = { "mockbin-path.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "oauth2",
      api_id = api2.id,
      config = {
        scopes = { "email", "profile" },
        enable_authorization_code = true,
        mandatory_scope = true,
        provision_key = "provision123",
        token_expiration = 5,
        enable_implicit_grant = true
      }
    })

    local api2bis = assert(helpers.dao.apis:insert {
      name = "api-2-bis",
      uris = { "/somepath" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "oauth2",
      api_id = api2bis.id,
      config = {
        scopes = { "email", "profile" },
        enable_authorization_code = true,
        mandatory_scope = true,
        provision_key = "provision123",
        token_expiration = 5,
        enable_implicit_grant = true
      }
    })

    local api3 = assert(helpers.dao.apis:insert {
      name = "api-3",
      hosts = { "oauth2_3.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "oauth2",
      api_id = api3.id,
      config = {
        scopes = { "email", "profile" },
        enable_authorization_code = true,
        mandatory_scope = true,
        provision_key = "provision123",
        token_expiration = 5,
        enable_implicit_grant = true,
        hide_credentials = true
      }
    })

    local api4 = assert(helpers.dao.apis:insert {
      name = "api-4",
      hosts = { "oauth2_4.com" },
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
      name = "api-5",
      hosts = { "oauth2_5.com" },
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
      name = "api-6",
      hosts = { "oauth2_6.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "oauth2",
      api_id = api6.id,
      config = {
        scopes = { "email", "profile", "user.email" },
        enable_authorization_code = true,
        mandatory_scope = true,
        provision_key = "provision123",
        token_expiration = 5,
        enable_implicit_grant = true,
        accept_http_if_already_terminated = true
      }
    })

    local api7 = assert(helpers.dao.apis:insert {
      name = "api-7",
      hosts = { "oauth2_7.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "oauth2",
      api_id = api7.id,
      config = {
        scopes = { "email", "profile", "user.email" },
        enable_authorization_code = true,
        mandatory_scope = true,
        provision_key = "provision123",
        token_expiration = 5,
        enable_implicit_grant = true,
        anonymous = anonymous_user.id,
        global_credentials = false
      }
    })

    local api8 = assert(helpers.dao.apis:insert {
      name = "oauth2_8.com",
      hosts = { "oauth2_8.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "oauth2",
      api_id = api8.id,
      config = {
        scopes = { "email", "profile", "user.email" },
        enable_authorization_code = true,
        mandatory_scope = true,
        provision_key = "provision123",
        token_expiration = 5,
        enable_implicit_grant = true,
        global_credentials = true
      }
    })

    local api9 = assert(helpers.dao.apis:insert {
      name = "oauth2_9.com",
      hosts = { "oauth2_9.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "oauth2",
      api_id = api9.id,
      config = {
        scopes = { "email", "profile", "user.email" },
        enable_authorization_code = true,
        mandatory_scope = true,
        provision_key = "provision123",
        token_expiration = 5,
        enable_implicit_grant = true,
        global_credentials = true
      }
    })

    local api10 = assert(helpers.dao.apis:insert {
      name = "oauth2_10.com",
      hosts = { "oauth2_10.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "oauth2",
      api_id = api10.id,
      config = {
        scopes = { "email", "profile", "user.email" },
        enable_authorization_code = true,
        mandatory_scope = true,
        provision_key = "provision123",
        token_expiration = 5,
        enable_implicit_grant = true,
        global_credentials = true,
        anonymous = utils.uuid(), -- a non existing consumer
      }
    })

    assert(helpers.start_kong())
    proxy_client = helpers.proxy_client()
    proxy_ssl_client = helpers.proxy_ssl_client()
  end)
  teardown(function()
    if proxy_client and proxy_ssl_client then
      proxy_client:close()
      proxy_ssl_client:close()
    end
    helpers.stop_kong()
  end)

  describe("OAuth2 Authorization", function()
    describe("Code Grant", function()
      it("returns an error when no provision_key is being sent", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          headers = {
            ["Host"] = "oauth2.com"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "Invalid provision_key", error = "invalid_provision_key" }, json)
        assert.are.equal("no-store", res.headers["cache-control"])
        assert.are.equal("no-cache", res.headers["pragma"])
      end)
      it("returns an error when no parameter is being sent", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          body = {
            provision_key = "provision123"
          },
          headers = {
            ["Host"] = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "Missing authenticated_userid parameter", error = "invalid_authenticated_userid" }, json)
      end)
      it("returns an error when only provision_key and authenticated_userid are sent", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          body = {
            provision_key = "provision123",
            authenticated_userid = "id123"
          },
          headers = {
            ["Host"] = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "Invalid client authentication", error = "invalid_client" }, json)
        assert.are.equal("no-store", res.headers["cache-control"])
        assert.are.equal("no-cache", res.headers["pragma"])
      end)
      it("returns an error when only the client_id is being sent", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          body = {
            provision_key = "provision123",
            authenticated_userid = "id123",
            client_id = "clientid123"
          },
          headers = {
            ["Host"] = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ redirect_uri = "http://google.com/kong?error=invalid_scope&error_description=You%20must%20specify%20a%20scope" }, json)
      end)
      it("returns an error when an invalid scope is being sent", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          body = {
            provision_key = "provision123",
            authenticated_userid = "id123",
            client_id = "clientid123",
            scope = "wot"
          },
          headers = {
            ["Host"] = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ redirect_uri = "http://google.com/kong?error=invalid_scope&error_description=%22wot%22%20is%20an%20invalid%20scope" }, json)
      end)
      it("returns an error when no response_type is being sent", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          body = {
            provision_key = "provision123",
            authenticated_userid = "id123",
            client_id = "clientid123",
            scope = "email"
          },
          headers = {
            ["Host"] = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ redirect_uri = "http://google.com/kong?error=unsupported_response_type&error_description=Invalid%20response_type" }, json)
      end)
      it("returns an error with a state when no response_type is being sent", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          body = {
            provision_key = "provision123",
            authenticated_userid = "id123",
            client_id = "clientid123",
            scope = "email",
            state = "somestate"
          },
          headers = {
            ["Host"] = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ redirect_uri = "http://google.com/kong?error=unsupported_response_type&error_description=Invalid%20response_type&state=somestate" }, json)
      end)
      it("returns error when the redirect_uri does not match", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          body = {
            provision_key = "provision123",
            authenticated_userid = "id123",
            client_id = "clientid123",
            scope = "email",
            response_type = "code",
            redirect_uri = "http://hello.com/"
          },
          headers = {
            ["Host"] = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ redirect_uri = "http://google.com/kong?error=invalid_request&error_description=Invalid%20redirect_uri%20that%20does%20not%20match%20with%20any%20redirect_uri%20created%20with%20the%20application" }, json)
      end)
      it("works even if redirect_uri contains a query string", function()
        local res = assert(proxy_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          body = {
            provision_key = "provision123",
            authenticated_userid = "id123",
            client_id = "clientid789",
            scope = "email",
            response_type = "code"
          },
          headers = {
            ["Host"] = "oauth2_6.com",
            ["Content-Type"] = "application/json",
            ["X-Forwarded-Proto"] = "https"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\?code=[\\w]{32,32}&foo=bar$"))
      end)
      it("works with multiple redirect_uri in the application", function()
        local res = assert(proxy_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          body = {
            provision_key = "provision123",
            authenticated_userid = "id123",
            client_id = "clientid456",
            scope = "email",
            response_type = "code"
          },
          headers = {
            ["Host"] = "oauth2_6.com",
            ["Content-Type"] = "application/json",
            ["X-Forwarded-Proto"] = "https"
          }
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.truthy(ngx.re.match(json.redirect_uri, "^http://one\\.com/one/\\?code=[\\w]{32,32}$"))
      end)
      it("fails when not under HTTPS", function()
        local res = assert(proxy_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          body = {
            provision_key = "provision123",
            authenticated_userid = "id123",
            client_id = "clientid123",
            scope = "email",
            response_type = "code"
          },
          headers = {
            ["Host"] = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        assert.response(res).has.status(400)
        local json = assert.response(res).has.jsonbody(res)

        assert.equal("You must use HTTPS", json.error_description)
        assert.equal("access_denied", json.error)
      end)
      it("works when not under HTTPS but accept_http_if_already_terminated is true", function()
        local res = assert(proxy_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          body = {
            provision_key = "provision123",
            authenticated_userid = "id123",
            client_id = "clientid123",
            scope = "email",
            response_type = "code"
          },
          headers = {
            ["Host"] = "oauth2_6.com",
            ["Content-Type"] = "application/json",
            ["X-Forwarded-Proto"] = "https"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\?code=[\\w]{32,32}$"))
      end)
      it("fails when not under HTTPS and accept_http_if_already_terminated is false", function()
        local res = assert(proxy_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          body = {
            provision_key = "provision123",
            authenticated_userid = "id123",
            client_id = "clientid123",
            scope = "email",
            response_type = "code"
          },
          headers = {
            ["Host"] = "oauth2.com",
            ["Content-Type"] = "application/json",
            ["X-Forwarded-Proto"] = "https"
          }
        })
        assert.response(res).has.status(400)
        local json = assert.response(res).has.jsonbody(res)

        assert.equal("You must use HTTPS", json.error_description)
        assert.equal("access_denied", json.error)
      end)
      it("returns success", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          body = {
            provision_key = "provision123",
            authenticated_userid = "id123",
            client_id = "clientid123",
            scope = "email",
            response_type = "code"
          },
          headers = {
            ["Host"] = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\?code=[\\w]{32,32}$"))
      end)
      it("fails with a path when using the DNS", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          body = {
            provision_key = "provision123a",
            authenticated_userid = "id123",
            client_id = "clientid123",
            scope = "email",
            response_type = "code"
          },
          headers = {
            ["Host"] = "mockbin-path.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "Invalid provision_key", error = "invalid_provision_key" }, json)
      end)
      it("returns success with a path", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/somepath/oauth2/authorize",
          body = {
            provision_key = "provision123",
            authenticated_userid = "id123",
            client_id = "clientid123",
            scope = "email",
            response_type = "code"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\?code=[\\w]{32,32}$"))
      end)
      it("returns success when requesting the url with final slash", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/authorize/",
          body = {
            provision_key = "provision123",
            authenticated_userid = "id123",
            client_id = "clientid123",
            scope = "email",
            response_type = "code"
          },
          headers = {
            ["Host"] = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\?code=[\\w]{32,32}$"))
      end)
      it("returns success with a state", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          body = {
            provision_key = "provision123",
            authenticated_userid = "id123",
            client_id = "clientid123",
            scope = "email",
            response_type = "code",
            state = "hello"
          },
          headers = {
            ["Host"] = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\?code=[\\w]{32,32}&state=hello$"))
        -- Checking headers
        assert.are.equal("no-store", res.headers["cache-control"])
        assert.are.equal("no-cache", res.headers["pragma"])
      end)
      it("returns success and store authenticated user properties", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          body = {
            provision_key = "provision123",
            client_id = "clientid123",
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
        local body = cjson.decode(assert.res_status(200, res))
        assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\?code=[\\w]{32,32}&state=hello$"))

        local iterator, err = ngx.re.gmatch(body.redirect_uri, "^http://google\\.com/kong\\?code=([\\w]{32,32})&state=hello$")
        assert.is_nil(err)
        local m, err = iterator()
        assert.is_nil(err)
        local data = helpers.dao.oauth2_authorization_codes:find_all {code = m[1]}
        assert.are.equal(1, #data)
        assert.are.equal(m[1], data[1].code)
        assert.are.equal("userid123", data[1].authenticated_userid)
        assert.are.equal("email", data[1].scope)
        assert.are.equal(client1.id, data[1].credential_id)
      end)
      it("returns success with a dotted scope and store authenticated user properties", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          body = {
            provision_key = "provision123",
            client_id = "clientid123",
            scope = "user.email",
            response_type = "code",
            state = "hello",
            authenticated_userid = "userid123"
          },
          headers = {
            ["Host"] = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\?code=[\\w]{32,32}&state=hello$"))

        local iterator, err = ngx.re.gmatch(body.redirect_uri, "^http://google\\.com/kong\\?code=([\\w]{32,32})&state=hello$")
        assert.is_nil(err)
        local m, err = iterator()
        assert.is_nil(err)
        local data = helpers.dao.oauth2_authorization_codes:find_all {code = m[1]}
        assert.are.equal(1, #data)
        assert.are.equal(m[1], data[1].code)
        assert.are.equal("userid123", data[1].authenticated_userid)
        assert.are.equal("user.email", data[1].scope)
      end)
    end)

    describe("Implicit Grant", function()
      it("returns success", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          body = {
            provision_key = "provision123",
            authenticated_userid = "id123",
            client_id = "clientid123",
            scope = "email",
            response_type = "token"
          },
          headers = {
            ["Host"] = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\#access_token=[\\w]{32,32}&expires_in=[\\d]+&token_type=bearer$"))
        assert.are.equal("no-store", res.headers["cache-control"])
        assert.are.equal("no-cache", res.headers["pragma"])
      end)
      it("returns success and the state", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          body = {
            provision_key = "provision123",
            authenticated_userid = "id123",
            client_id = "clientid123",
            scope = "email",
            response_type = "token",
            state = "wot"
          },
          headers = {
            ["Host"] = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\#access_token=[\\w]{32,32}&expires_in=[\\d]+&state=wot&token_type=bearer$"))
      end)
      it("returns success and the token should have the right expiration", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          body = {
            provision_key = "provision123",
            authenticated_userid = "id123",
            client_id = "clientid123",
            scope = "email",
            response_type = "token"
          },
          headers = {
            ["Host"] = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\#access_token=[\\w]{32,32}&expires_in=[\\d]+&token_type=bearer$"))

        local iterator, err = ngx.re.gmatch(body.redirect_uri, "^http://google\\.com/kong\\#access_token=([\\w]{32,32})&expires_in=[\\d]+&token_type=bearer$")
        assert.is_nil(err)
        local m, err = iterator()
        assert.is_nil(err)
        local data = helpers.dao.oauth2_tokens:find_all {access_token = m[1]}
        assert.are.equal(1, #data)
        assert.are.equal(m[1], data[1].access_token)
        assert.are.equal(5, data[1].expires_in)
        assert.falsy(data[1].refresh_token)
      end)
      it("returns success and store authenticated user properties", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          body = {
            provision_key = "provision123",
            client_id = "clientid123",
            scope = "email  profile",
            response_type = "token",
            authenticated_userid = "userid123"
          },
          headers = {
            ["Host"] = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.is_table(ngx.re.match(body.redirect_uri, "^http://google\\.com/kong\\#access_token=[\\w]{32,32}&expires_in=[\\d]+&token_type=bearer$"))

        local iterator, err = ngx.re.gmatch(body.redirect_uri, "^http://google\\.com/kong\\#access_token=([\\w]{32,32})&expires_in=[\\d]+&token_type=bearer$")
        assert.is_nil(err)
        local m, err = iterator()
        assert.is_nil(err)
        local data = helpers.dao.oauth2_tokens:find_all {access_token = m[1]}
        assert.are.equal(1, #data)
        assert.are.equal(m[1], data[1].access_token)
        assert.are.equal("userid123", data[1].authenticated_userid)
        assert.are.equal("email profile", data[1].scope)

        -- Checking that there is no refresh token since it's an implicit grant
        assert.are.equal(5, data[1].expires_in)
        assert.falsy(data[1].refresh_token)
      end)
      it("returns set the right upstream headers", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/authorize",
          body = {
            provision_key = "provision123",
            client_id = "clientid123",
            scope = "email  profile",
            response_type = "token",
            authenticated_userid = "userid123"
          },
          headers = {
            ["Host"] = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        local iterator, err = ngx.re.gmatch(body.redirect_uri, "^http://google\\.com/kong\\#access_token=([\\w]{32,32})&expires_in=[\\d]+&token_type=bearer$")
        assert.is_nil(err)
        local m, err = iterator()
        assert.is_nil(err)
        local access_token = m[1]

        local res = assert(proxy_ssl_client:send {
          method = "GET",
          path = "/request?access_token="..access_token,
          headers = {
            ["Host"] = "oauth2.com"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.truthy(body.headers["x-consumer-id"])
        assert.are.equal("bob", body.headers["x-consumer-username"])
        assert.are.equal("email profile", body.headers["x-authenticated-scope"])
        assert.are.equal("userid123", body.headers["x-authenticated-userid"])
      end)
    end)

    describe("Client Credentials", function()
      it("returns an error when client_secret is not sent", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            client_id = "clientid123",
            scope = "email",
            response_type = "token"
          },
          headers = {
            ["Host"] = "oauth2_4.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "Invalid client authentication", error = "invalid_client" }, json)
      end)
      it("returns an error when client_secret is not sent", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            client_id = "clientid123",
            client_secret="secret123",
            scope = "email",
            response_type = "token"
          },
          headers = {
            ["Host"] = "oauth2_4.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error = "unsupported_grant_type", error_description = "Invalid grant_type" }, json)
      end)
      it("fails when not under HTTPS", function()
        local res = assert(proxy_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            client_id = "clientid123",
            client_secret="secret123",
            scope = "email",
            grant_type = "client_credentials"
          },
          headers = {
            ["Host"] = "oauth2_4.com",
            ["Content-Type"] = "application/json"
          }
        })
        assert.response(res).has.status(400)
        local json = assert.response(res).has.jsonbody(res)

        assert.equal("You must use HTTPS", json.error_description)
        assert.equal("access_denied", json.error)
      end)
      it("fails when setting authenticated_userid and no provision_key", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            client_id = "clientid123",
            client_secret="secret123",
            scope = "email",
            grant_type = "client_credentials",
            authenticated_userid = "user123"
          },
          headers = {
            ["Host"] = "oauth2_4.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "Invalid provision_key", error = "invalid_provision_key" }, json)
      end)
      it("fails when setting authenticated_userid and invalid provision_key", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            client_id = "clientid123",
            client_secret="secret123",
            scope = "email",
            grant_type = "client_credentials",
            authenticated_userid = "user123",
            provision_key = "hello"
          },
          headers = {
            ["Host"] = "oauth2_4.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "Invalid provision_key", error = "invalid_provision_key" }, json)
      end)
      it("returns success", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            client_id = "clientid123",
            client_secret="secret123",
            scope = "email",
            grant_type = "client_credentials"
          },
          headers = {
            ["Host"] = "oauth2_4.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        assert.is_table(ngx.re.match(body, [[^\{"token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
      end)
      it("returns success with an application that has multiple redirect_uri", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            client_id = "clientid456",
            client_secret="secret456",
            scope = "email",
            grant_type = "client_credentials"
          },
          headers = {
            ["Host"] = "oauth2_4.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        assert.is_table(ngx.re.match(body, [[^\{"token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
      end)
      it("returns success with an application that has multiple redirect_uri, and by passing a valid redirect_uri", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            client_id = "clientid456",
            client_secret="secret456",
            scope = "email",
            grant_type = "client_credentials",
            redirect_uri = "http://two.com/two"
          },
          headers = {
            ["Host"] = "oauth2_4.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        assert.is_table(ngx.re.match(body, [[^\{"token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
      end)
      it("fails with an application that has multiple redirect_uri, and by passing an invalid redirect_uri", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            client_id = "clientid456",
            client_secret="secret456",
            scope = "email",
            grant_type = "client_credentials",
            redirect_uri = "http://two.com/two/hello"
          },
          headers = {
            ["Host"] = "oauth2_4.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error = "invalid_request", error_description = "Invalid redirect_uri that does not match with any redirect_uri created with the application" }, json)
      end)
      it("returns success with authenticated_userid and valid provision_key", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            client_id = "clientid123",
            client_secret="secret123",
            scope = "email",
            grant_type = "client_credentials",
            authenticated_userid = "hello",
            provision_key = "provision123"
          },
          headers = {
            ["Host"] = "oauth2_4.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        assert.is_table(ngx.re.match(body, [[^\{"token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
      end)
      it("returns success with authorization header", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            scope = "email",
            grant_type = "client_credentials"
          },
          headers = {
            ["Host"] = "oauth2_4.com",
            ["Content-Type"] = "application/json",
            Authorization = "Basic Y2xpZW50aWQxMjM6c2VjcmV0MTIz"
          }
        })
        local body = assert.res_status(200, res)
        assert.is_table(ngx.re.match(body, [[^\{"token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
      end)
      it("returns an error with a wrong authorization header", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            scope = "email",
            grant_type = "client_credentials"
          },
          headers = {
            ["Host"] = "oauth2_4.com",
            ["Content-Type"] = "application/json",
            Authorization = "Basic Y2xpZW50aWQxMjM6c2VjcmV0MTI0"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "Invalid client authentication", error = "invalid_client" }, json)
        assert.are.equal("Basic realm=\"OAuth2.0\"", res.headers["www-authenticate"])
      end)
      it("sets the right upstream headers", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            client_id = "clientid123",
            client_secret="secret123",
            scope = "email",
            grant_type = "client_credentials",
            authenticated_userid = "hello",
            provision_key = "provision123"
          },
          headers = {
            ["Host"] = "oauth2_4.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))

        local res = assert(proxy_ssl_client:send {
          method = "GET",
          path = "/request?access_token="..body.access_token,
          headers = {
            ["Host"] = "oauth2_4.com"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.truthy(body.headers["x-consumer-id"])
        assert.are.equal("bob", body.headers["x-consumer-username"])
        assert.are.equal("email", body.headers["x-authenticated-scope"])
        assert.are.equal("hello", body.headers["x-authenticated-userid"])
      end)
      it("works in a multipart request", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            client_id = "clientid123",
            client_secret="secret123",
            scope = "email",
            grant_type = "client_credentials",
            authenticated_userid = "hello",
            provision_key = "provision123"
          },
          headers = {
            ["Host"] = "oauth2_4.com",
            ["Content-Type"] = "multipart/form-data"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))

        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/request",
          body = {
            access_token = body.access_token
          },
          headers = {
            ["Host"] = "oauth2_4.com",
            ["Content-Type"] = "multipart/form-data"
          }
        })
        assert.res_status(200, res)
      end)
    end)

    describe("Password Grant", function()
      it("blocks unauthorized requests", function()
        local res = assert(proxy_ssl_client:send {
          method = "GET",
          path = "/request",
          headers = {
            ["Host"] = "oauth2_5.com"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "The access token is missing", error = "invalid_request" }, json)
      end)
      it("returns an error when client_secret is not sent", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            client_id = "clientid123",
            scope = "email",
            response_type = "token"
          },
          headers = {
            ["Host"] = "oauth2_5.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "Invalid client authentication", error = "invalid_client" }, json)
      end)
      it("returns an error when grant_type is not sent", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            client_id = "clientid123",
            client_secret="secret123",
            scope = "email",
            response_type = "token"
          },
          headers = {
            ["Host"] = "oauth2_5.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error = "unsupported_grant_type", error_description = "Invalid grant_type" }, json)
      end)
      it("fails when no provision key is being sent", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            client_id = "clientid123",
            client_secret="secret123",
            scope = "email",
            response_type = "token",
            grant_type = "password"
          },
          headers = {
            ["Host"] = "oauth2_5.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "Invalid provision_key", error = "invalid_provision_key" }, json)
      end)
      it("fails when no provision key is being sent", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            client_id = "clientid123",
            client_secret="secret123",
            scope = "email",
            grant_type = "password"
          },
          headers = {
            ["Host"] = "oauth2_5.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "Invalid provision_key", error = "invalid_provision_key" }, json)
      end)
      it("fails when no authenticated user id is being sent", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            provision_key = "provision123",
            client_id = "clientid123",
            client_secret="secret123",
            scope = "email",
            grant_type = "password"
          },
          headers = {
            ["Host"] = "oauth2_5.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "Missing authenticated_userid parameter", error = "invalid_authenticated_userid" }, json)
      end)
      it("returns success", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            provision_key = "provision123",
            authenticated_userid = "id123",
            client_id = "clientid123",
            client_secret="secret123",
            scope = "email",
            grant_type = "password"
          },
          headers = {
            ["Host"] = "oauth2_5.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        assert.is_table(ngx.re.match(body, [[^\{"refresh_token":"[\w]{32,32}","token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
      end)
      it("returns success with authorization header", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            provision_key = "provision123",
            authenticated_userid = "id123",
            scope = "email",
            grant_type = "password"
          },
          headers = {
            ["Host"] = "oauth2_5.com",
            ["Content-Type"] = "application/json",
            Authorization = "Basic Y2xpZW50aWQxMjM6c2VjcmV0MTIz"
          }
        })
        local body = assert.res_status(200, res)
        assert.is_table(ngx.re.match(body, [[^\{"refresh_token":"[\w]{32,32}","token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
      end)
      it("returns an error with a wrong authorization header", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            provision_key = "provision123",
            authenticated_userid = "id123",
            scope = "email",
            grant_type = "password"
          },
          headers = {
            ["Host"] = "oauth2_5.com",
            ["Content-Type"] = "application/json",
            Authorization = "Basic Y2xpZW50aWQxMjM6c2VjcmV0MTI0"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ error_description = "Invalid client authentication", error = "invalid_client" }, json)
        assert.are.equal("Basic realm=\"OAuth2.0\"", res.headers["www-authenticate"])
      end)
      it("sets the right upstream headers", function()
        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            provision_key = "provision123",
            authenticated_userid = "id123",
            scope = "email",
            grant_type = "password"
          },
          headers = {
            ["Host"] = "oauth2_5.com",
            ["Content-Type"] = "application/json",
            Authorization = "Basic Y2xpZW50aWQxMjM6c2VjcmV0MTIz"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))

        local res = assert(proxy_ssl_client:send {
          method = "GET",
          path = "/request?access_token="..body.access_token,
          headers = {
            ["Host"] = "oauth2_5.com"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.truthy(body.headers["x-consumer-id"])
        assert.are.equal("bob", body.headers["x-consumer-username"])
        assert.are.equal("email", body.headers["x-authenticated-scope"])
        assert.are.equal("id123", body.headers["x-authenticated-userid"])
      end)
    end)
  end)

  describe("OAuth2 Access Token", function()
    it("returns an error when nothing is being sent", function()
      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/oauth2/token",
        headers = {
          ["Host"] = "oauth2.com"
        }
      })
      local body = assert.res_status(400, res)
      local json = cjson.decode(body)
      assert.same({ error_description = "Invalid client authentication", error = "invalid_client" }, json)
      -- Checking headers
      assert.are.equal("no-store", res.headers["cache-control"])
      assert.are.equal("no-cache", res.headers["pragma"])
    end)
    it("returns an error when only the code is being sent", function()
      local code = provision_code()

      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/oauth2/token",
        body = {
          code = code
        },
        headers = {
          ["Host"] = "oauth2.com",
          ["Content-Type"] = "application/json"
        }
      })
      local body = assert.res_status(400, res)
      local json = cjson.decode(body)
      assert.same({ error_description = "Invalid client authentication", error = "invalid_client" }, json)
      -- Checking headers
      assert.are.equal("no-store", res.headers["cache-control"])
      assert.are.equal("no-cache", res.headers["pragma"])
    end)
    it("returns an error when only the code and client_secret are being sent", function()
      local code = provision_code()

      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/oauth2/token",
        body = {
          code = code,
          client_secret = "secret123"
        },
        headers = {
          ["Host"] = "oauth2.com",
          ["Content-Type"] = "application/json"
        }
      })
      local body = assert.res_status(400, res)
      local json = cjson.decode(body)
      assert.same({ error_description = "Invalid client authentication", error = "invalid_client" }, json)
      -- Checking headers
      assert.are.equal("no-store", res.headers["cache-control"])
      assert.are.equal("no-cache", res.headers["pragma"])
    end)
    it("returns an error when grant_type is not being sent", function()
      local code = provision_code()

      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/oauth2/token",
        body = {
          code = code,
          client_id = "clientid123",
          client_secret = "secret123"
        },
        headers = {
          ["Host"] = "oauth2.com",
          ["Content-Type"] = "application/json"
        }
      })
      local body = assert.res_status(400, res)
      local json = cjson.decode(body)
      assert.same({ error = "unsupported_grant_type", error_description = "Invalid grant_type" }, json)
    end)
    it("returns an error with a wrong code", function()
      local code = provision_code()

      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/oauth2/token",
        body = {
          code = code.."hello",
          client_id = "clientid123",
          client_secret = "secret123",
          grant_type = "authorization_code"
        },
        headers = {
          ["Host"] = "oauth2.com",
          ["Content-Type"] = "application/json"
        }
      })
      local body = assert.res_status(400, res)
      local json = cjson.decode(body)
      assert.same({ error = "invalid_request", error_description = "Invalid code" }, json)
    end)
    it("returns success without state", function()
      local code = provision_code()

      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/oauth2/token",
        body = {
          code = code,
          client_id = "clientid123",
          client_secret = "secret123",
          grant_type = "authorization_code"
        },
        headers = {
          ["Host"] = "oauth2.com",
          ["Content-Type"] = "application/json"
        }
      })
      local body = assert.res_status(200, res)
      assert.is_table(ngx.re.match(body, [[^\{"refresh_token":"[\w]{32,32}","token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
    end)
    it("returns success with state", function()
      local code = provision_code()

      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/oauth2/token",
        body = {
          code = code,
          client_id = "clientid123",
          client_secret = "secret123",
          grant_type = "authorization_code",
          state = "wot"
        },
        headers = {
          ["Host"] = "oauth2.com",
          ["Content-Type"] = "application/json"
        }
      })
      local body = assert.res_status(200, res)
      assert.is_table(ngx.re.match(body, [[^\{"refresh_token":"[\w]{32,32}","token_type":"bearer","state":"wot","access_token":"[\w]{32,32}","expires_in":5\}$]]))
    end)
    it("sets the right upstream headers", function()
      local code = provision_code()
      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/oauth2/token",
        body = {
          code = code,
          client_id = "clientid123",
          client_secret = "secret123",
          grant_type = "authorization_code"
        },
        headers = {
          ["Host"] = "oauth2.com",
          ["Content-Type"] = "application/json"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))

      local res = assert(proxy_ssl_client:send {
        method = "GET",
        path = "/request?access_token="..body.access_token,
        headers = {
          ["Host"] = "oauth2.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.truthy(body.headers["x-consumer-id"])
      assert.are.equal("bob", body.headers["x-consumer-username"])
      assert.are.equal("email", body.headers["x-authenticated-scope"])
      assert.are.equal("userid123", body.headers["x-authenticated-userid"])
    end)
    it("fails when an authorization code is used more than once", function()
      local code = provision_code()

      local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            code = code,
            client_id = "clientid123",
            client_secret = "secret123",
            grant_type = "authorization_code"
          },
          headers = {
            ["Host"] = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        assert.is_table(ngx.re.match(body, [[^\{"refresh_token":"[\w]{32,32}","token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))

        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            code = code,
            client_id = "clientid123",
            client_secret = "secret123",
            grant_type = "authorization_code"
          },
          headers = {
            ["Host"] = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error = "invalid_request", error_description = "Invalid code" }, json)
    end)
    it("fails when an authorization code is used by another application", function()
      local code = provision_code()

      local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/oauth2/token",
          body = {
            code = code,
            client_id = "clientid789",
            client_secret = "secret789",
            grant_type = "authorization_code"
          },
          headers = {
            ["Host"] = "oauth2.com",
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ error = "invalid_request", error_description = "Invalid code" }, json)
    end)

    it("fails when an authorization code is used for another API", function()
      local code = provision_code()
      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/oauth2/token",
        body = {
          code = code,
          client_id = "clientid123",
          client_secret = "secret123",
          grant_type = "authorization_code"
        },
        headers = {
          ["Host"] = "oauth2_3.com",
          ["Content-Type"] = "application/json"
        }
      })
      local body = assert.res_status(400, res)
      local json = cjson.decode(body)
      assert.same({ error = "invalid_request", error_description = "Invalid code" }, json)
    end)
  end)

  describe("Making a request", function()
    it("fails when no access_token is being sent in an application/json body", function()
      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/request",
        headers = {
          ["Host"] = "oauth2.com",
          ["Content-Type"] = "application/json"
        }
      })
      local body = assert.res_status(401, res)
      local json = cjson.decode(body)
      assert.same({ error_description = "The access token is missing", error = "invalid_request" }, json)
    end)
    it("works when a correct access_token is being sent in the querystring", function()
      local token = provision_token()

      local res = assert(proxy_ssl_client:send {
        method = "GET",
        path = "/request?access_token="..token.access_token,
        headers = {
          ["Host"] = "oauth2.com"
        }
      })
      assert.res_status(200, res)
    end)
    it("does not work when requesting a different API", function()
      local token = provision_token()

      local res = assert(proxy_ssl_client:send {
        method = "GET",
        path = "/request?access_token="..token.access_token,
        headers = {
          ["Host"] = "oauth2_3.com"
        }
      })
      local body = assert.res_status(401, res)
      local json = cjson.decode(body)
      assert.same({ error_description = "The access token is invalid or has expired", error = "invalid_token" }, json)
    end)
    it("works when a correct access_token is being sent in a form body", function()
      local token = provision_token()

      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/request",
        body = {
          access_token = token.access_token
        },
        headers = {
          ["Host"] = "oauth2.com",
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(200, res)
    end)
    it("works when a correct access_token is being sent in an authorization header (bearer)", function()
      local token = provision_token()

      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/request",
        headers = {
          ["Host"] = "oauth2.com",
          Authorization = "bearer "..token.access_token
        }
      })
      assert.res_status(200, res)
    end)
    it("works when a correct access_token is being sent in an authorization header (token)", function()
      local token = provision_token()

      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/request",
        headers = {
          ["Host"] = "oauth2.com",
          Authorization = "bearer "..token.access_token
        }
      })
      local body = cjson.decode(assert.res_status(200, res))

      local consumer = helpers.dao.consumers:find_all({username = "bob"})[1]
      assert.are.equal(consumer.id, body.headers["x-consumer-id"])
      assert.are.equal(consumer.username, body.headers["x-consumer-username"])
      assert.are.equal("userid123", body.headers["x-authenticated-userid"])
      assert.are.equal("email", body.headers["x-authenticated-scope"])
      assert.is_nil(body.headers["x-anonymous-consumer"])
    end)
    it("works with right credentials and anonymous", function()
      local token = provision_token("oauth2_7.com")

      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/request",
        headers = {
          ["Host"] = "oauth2_7.com",
          Authorization = "bearer "..token.access_token
        }
      })
      local body = cjson.decode(assert.res_status(200, res))

      local consumer = helpers.dao.consumers:find_all({username = "bob"})[1]
      assert.are.equal(consumer.id, body.headers["x-consumer-id"])
      assert.are.equal(consumer.username, body.headers["x-consumer-username"])
      assert.are.equal("userid123", body.headers["x-authenticated-userid"])
      assert.are.equal("email", body.headers["x-authenticated-scope"])
      assert.is_nil(body.headers["x-anonymous-consumer"])
    end)
    it("works with wrong credentials and anonymous", function()
      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/request",
        headers = {
          ["Host"] = "oauth2_7.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.are.equal("true", body.headers["x-anonymous-consumer"])
      assert.equal('no-body', body.headers["x-consumer-username"])
    end)
    it("errors when anonymous user doesn't exist", function()
      local res = assert(proxy_ssl_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "oauth2_10.com"
        }
      })
      assert.response(res).has.status(500)
    end)
    describe("Global Credentials", function()
      it("does not access two different APIs that are not sharing global credentials", function()
        local token = provision_token("oauth2_8.com")

        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/request",
          headers = {
            ["Host"] = "oauth2_8.com",
            Authorization = "bearer "..token.access_token
          }
        })
        assert.res_status(200, res)

        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/request",
          headers = {
            ["Host"] = "oauth2.com",
            Authorization = "bearer "..token.access_token
          }
        })
        assert.res_status(401, res)
      end)
      it("does not access two different APIs that are not sharing global credentials 2", function()
        local token = provision_token("oauth2.com")

        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/request",
          headers = {
            ["Host"] = "oauth2_8.com",
            Authorization = "bearer "..token.access_token
          }
        })
        assert.res_status(401, res)

        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/request",
          headers = {
            ["Host"] = "oauth2.com",
            Authorization = "bearer "..token.access_token
          }
        })
        assert.res_status(200, res)
      end)
      it("access two different APIs that are sharing global credentials", function()
        local token = provision_token("oauth2_8.com")

        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/request",
          headers = {
            ["Host"] = "oauth2_8.com",
            Authorization = "bearer "..token.access_token
          }
        })
        assert.res_status(200, res)

        local res = assert(proxy_ssl_client:send {
          method = "POST",
          path = "/request",
          headers = {
            ["Host"] = "oauth2_9.com",
            Authorization = "bearer "..token.access_token
          }
        })
        assert.res_status(200, res)
      end)
    end)
  end)

  describe("Authentication challenge", function()
    it("returns 401 Unauthorized without error if it lacks any authentication information", function()
      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/request",
        headers = {
          ["Host"] = "oauth2.com"
        }
      })
      local body = assert.res_status(401, res)
      local json = cjson.decode(body)
      assert.same({ error_description = "The access token is missing", error = "invalid_request" }, json)
      assert.are.equal('Bearer realm="service"', res.headers['www-authenticate'])
    end)
    it("returns 401 Unauthorized when an invalid access token is being sent via url parameter", function()
      local res = assert(proxy_ssl_client:send {
        method = "GET",
        path = "/request?access_token=invalid",
        headers = {
          ["Host"] = "oauth2.com"
        }
      })
      local body = assert.res_status(401, res)
      local json = cjson.decode(body)
      assert.same({ error_description = "The access token is invalid or has expired", error = "invalid_token" }, json)
      assert.are.equal('Bearer realm="service" error="invalid_token" error_description="The access token is invalid or has expired"', res.headers['www-authenticate'])
    end)
    it("returns 401 Unauthorized when an invalid access token is being sent via the Authorization header", function()
      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/request",
        headers = {
          ["Host"] = "oauth2.com",
          Authorization = "bearer invalid"
        }
      })
      local body = assert.res_status(401, res)
      local json = cjson.decode(body)
      assert.same({ error_description = "The access token is invalid or has expired", error = "invalid_token" }, json)
      assert.are.equal('Bearer realm="service" error="invalid_token" error_description="The access token is invalid or has expired"', res.headers['www-authenticate'])
    end)
    it("returns 401 Unauthorized when token has expired", function()
      local token = provision_token()

      -- Token expires in (5 seconds)
      ngx.sleep(7)

      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/request",
        headers = {
          ["Host"] = "oauth2.com",
          Authorization = "bearer "..token.access_token
        }
      })
      local body = assert.res_status(401, res)
      local json = cjson.decode(body)
      assert.same({ error_description = "The access token is invalid or has expired", error = "invalid_token" }, json)
      assert.are.equal('Bearer realm="service" error="invalid_token" error_description="The access token is invalid or has expired"', res.headers['www-authenticate'])
    end)
  end)

  describe("Refresh Token", function()
    it("does not refresh an invalid access token", function()
      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/oauth2/token",
        body = {
          refresh_token = "hello",
          client_id = "clientid123",
          client_secret = "secret123",
          grant_type = "refresh_token"
        },
        headers = {
          ["Host"] = "oauth2.com",
          ["Content-Type"] = "application/json"
        }
      })
      local body = assert.res_status(400, res)
      local json = cjson.decode(body)
      assert.same({ error = "invalid_request", error_description = "Invalid refresh_token" }, json)
    end)
    it("refreshes an valid access token", function()
      local token = provision_token()

      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/oauth2/token",
        body = {
          refresh_token = token.refresh_token,
          client_id = "clientid123",
          client_secret = "secret123",
          grant_type = "refresh_token"
        },
        headers = {
          ["Host"] = "oauth2.com",
          ["Content-Type"] = "application/json"
        }
      })
      local body = assert.res_status(200, res)
      assert.is_table(ngx.re.match(body, [[^\{"refresh_token":"[\w]{32,32}","token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))
    end)
    it("expires after 5 seconds", function()
      local token = provision_token()

      local res = assert(proxy_client:send {
        method = "POST",
        path = "/request",
        headers = {
          ["Host"] = "oauth2.com",
          authorization = "bearer "..token.access_token
        }
      })
      assert.res_status(200, res)

      local id = helpers.dao.oauth2_tokens:find_all({access_token = token.access_token })[1].id
      assert.truthy(helpers.dao.oauth2_tokens:find({id=id}))

      -- But waiting after the cache expiration (5 seconds) should block the request
      ngx.sleep(7)

      local res = assert(proxy_client:send {
        method = "POST",
        path = "/request",
        headers = {
          ["Host"] = "oauth2.com",
          authorization = "bearer "..token.access_token
        }
      })
      local body = assert.res_status(401, res)
      local json = cjson.decode(body)
      assert.same({ error_description = "The access token is invalid or has expired", error = "invalid_token" }, json)

      -- Refreshing the token
      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/oauth2/token",
        body = {
          refresh_token = token.refresh_token,
          client_id = "clientid123",
          client_secret = "secret123",
          grant_type = "refresh_token"
        },
        headers = {
          ["Host"] = "oauth2.com",
          ["Content-Type"] = "application/json",
          authorization = "bearer "..token.access_token
        }
      })
      local body = assert.res_status(200, res)
      assert.is_table(ngx.re.match(body, [[^\{"refresh_token":"[\w]{32,32}","token_type":"bearer","access_token":"[\w]{32,32}","expires_in":5\}$]]))

      assert.falsy(token.access_token == cjson.decode(body).access_token)
      assert.falsy(token.refresh_token == cjson.decode(body).refresh_token)

      assert.falsy(helpers.dao.oauth2_tokens:find({id=id}))
    end)
  end)

  describe("Hide Credentials", function()
    it("does not hide credentials in the body", function()
      local token = provision_token()

      local res = assert(proxy_client:send {
        method = "POST",
        path = "/request",
        body = {
          access_token = token.access_token
        },
        headers = {
          ["Host"] = "oauth2.com",
          ["Content-Type"] = "application/x-www-form-urlencoded"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal(token.access_token, body.postData.params.access_token)
    end)
    it("hides credentials in the body", function()
      local token = provision_token("oauth2_3.com")

      local res = assert(proxy_client:send {
        method = "POST",
        path = "/request",
        body = {
          access_token = token.access_token
        },
        headers = {
          ["Host"] = "oauth2_3.com",
          ["Content-Type"] = "application/x-www-form-urlencoded"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.is_nil(body.postData.params.access_token)
    end)
    it("does not hide credentials in the querystring", function()
      local token = provision_token()

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request?access_token="..token.access_token,
        headers = {
          ["Host"] = "oauth2.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal(token.access_token, body.queryString.access_token)
    end)
    it("hides credentials in the querystring", function()
      local token = provision_token("oauth2_3.com")

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request?access_token="..token.access_token,
        headers = {
          ["Host"] = "oauth2_3.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.is_nil(body.queryString.access_token)
    end)
    it("does not hide credentials in the header", function()
      local token = provision_token()

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "oauth2.com",
          authorization = "bearer "..token.access_token
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal("bearer "..token.access_token, body.headers.authorization)
    end)
    it("hides credentials in the header", function()
      local token = provision_token("oauth2_3.com")

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "oauth2_3.com",
          authorization = "bearer "..token.access_token
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.is_nil(body.headers.authorization)
    end)
    it("does not abort when the request body is a multipart form upload", function()
      local token = provision_token("oauth2_3.com")

      local res = assert(proxy_client:send {
        method = "POST",
        path = "/request?access_token="..token.access_token,
        body = {
          foo = "bar"
        },
        headers = {
          ["Host"] = "oauth2_3.com",
          ["Content-Type"] = "multipart/form-data"
        }
      })
      assert.res_status(200, res)
    end)
  end)
end)


describe("#ci Plugin: oauth2 (access)", function()

  local client, user1, user2, anonymous

  setup(function()
    local api1 = assert(helpers.dao.apis:insert {
      name = "api-1",
      hosts = { "logical-and.com" },
      upstream_url = "http://mockbin.org/request"
    })
    assert(helpers.dao.plugins:insert {
      name = "oauth2",
      api_id = api1.id,
      config = {
        scopes = { "email", "profile", "user.email" },
        enable_authorization_code = true,
        mandatory_scope = true,
        provision_key = "provision123",
        token_expiration = 5,
        enable_implicit_grant = true,
        global_credentials = false,
      }
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api1.id
    })

    anonymous = assert(helpers.dao.consumers:insert {
      username = "Anonymous"
    })
    user1 = assert(helpers.dao.consumers:insert {
      username = "Mickey"
    })
    user2 = assert(helpers.dao.consumers:insert {
      username = "Aladdin"
    })

    local api2 = assert(helpers.dao.apis:insert {
      name = "api-2",
      hosts = { "logical-or.com" },
      upstream_url = "http://mockbin.org/request"
    })
    assert(helpers.dao.plugins:insert {
      name = "oauth2",
      api_id = api2.id,
      config = {
        scopes = { "email", "profile", "user.email" },
        enable_authorization_code = true,
        mandatory_scope = true,
        provision_key = "provision123",
        token_expiration = 5,
        enable_implicit_grant = true,
        global_credentials = false,
        anonymous = anonymous.id,
      }
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api2.id,
      config = {
        anonymous = anonymous.id
      }
    })

    assert(helpers.dao.keyauth_credentials:insert {
      key = "Mouse",
      consumer_id = user1.id
    })

    assert(helpers.dao.oauth2_credentials:insert {
      client_id = "clientid123",
      client_secret = "secret123",
      redirect_uri = "http://google.com/kong",
      name = "testapp",
      consumer_id = user2.id
    })

    assert(helpers.start_kong())
    client = helpers.proxy_client()
  end)


  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  describe("multiple auth without anonymous, logical AND", function()

    it("passes with all credentials provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-and.com",
          ["apikey"] = "Mouse",
          -- we must provide the apikey again in the extra_headers, for the
          -- token endpoint, because that endpoint is also protected by the
          -- key-auth plugin. Otherwise getting the token simply fails.
          ["Authorization"] = "bearer "..provision_token("logical-and.com",
            {["apikey"] = "Mouse"}).access_token,
        }
      })
      assert.response(res).has.status(200)
      assert.request(res).has.no.header("x-anonymous-consumer")
      local id = assert.request(res).has.header("x-consumer-id")
      assert.not_equal(id, anonymous.id)
      assert(id == user1.id or id == user2.id)
    end)

    it("fails 401, with only the first credential provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-and.com",
          ["apikey"] = "Mouse",
        }
      })
      assert.response(res).has.status(401)
    end)

    it("fails 401, with only the second credential provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-and.com",
          -- we must provide the apikey again in the extra_headers, for the
          -- token endpoint, because that endpoint is also protected by the
          -- key-auth plugin. Otherwise getting the token simply fails.
          ["Authorization"] = "bearer "..provision_token("logical-and.com",
            {["apikey"] = "Mouse"}).access_token,
        }
      })
      assert.response(res).has.status(401)
    end)

    it("fails 401, with no credential provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-and.com",
        }
      })
      assert.response(res).has.status(401)
    end)

  end)

  describe("multiple auth with anonymous, logical OR", function()

    it("passes with all credentials provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-or.com",
          ["apikey"] = "Mouse",
          ["Authorization"] = "bearer "..provision_token("logical-or.com").access_token,
        }
      })
      assert.response(res).has.status(200)
      assert.request(res).has.no.header("x-anonymous-consumer")
      local id = assert.request(res).has.header("x-consumer-id")
      assert.not_equal(id, anonymous.id)
      assert(id == user1.id or id == user2.id)
    end)

    it("passes with only the first credential provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-or.com",
          ["apikey"] = "Mouse",
        }
      })
      assert.response(res).has.status(200)
      assert.request(res).has.no.header("x-anonymous-consumer")
      local id = assert.request(res).has.header("x-consumer-id")
      assert.not_equal(id, anonymous.id)
      assert.equal(user1.id, id)
    end)

    it("passes with only the second credential provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-or.com",
          ["Authorization"] = "bearer "..provision_token("logical-or.com").access_token,
        }
      })
      assert.response(res).has.status(200)
      assert.request(res).has.no.header("x-anonymous-consumer")
      local id = assert.request(res).has.header("x-consumer-id")
      assert.not_equal(id, anonymous.id)
      assert.equal(user2.id, id)
    end)

    it("passes with no credential provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-or.com",
        }
      })
      assert.response(res).has.status(200)
      assert.request(res).has.header("x-anonymous-consumer")
      local id = assert.request(res).has.header("x-consumer-id")
      assert.equal(id, anonymous.id)
    end)

  end)

end)
