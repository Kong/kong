local cjson = require "cjson"
local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
describe("Plugin: oauth2 (invalidations)", function()
  local admin_client, proxy_ssl_client
  local db
  local dao
  local bp

  setup(function()
    bp, db, dao = helpers.get_db_utils(strategy)
  end)


  before_each(function()
    assert(db:truncate("routes"))
    assert(db:truncate("services"))
    assert(db:truncate("consumers"))
    assert(db:truncate("plugins"))
    dao:truncate_table("apis")
    dao:truncate_table("oauth2_tokens")
    dao:truncate_table("oauth2_credentials")
    dao:truncate_table("oauth2_authorization_codes")

    local api = assert(dao.apis:insert {
      name         = "api-1",
      hosts        = { "oauth2.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(db.plugins:insert {
      name   = "oauth2",
      api = { id = api.id },
      config = {
        scopes                    = { "email", "profile" },
        enable_authorization_code = true,
        mandatory_scope           = true,
        provision_key             = "provision123",
        token_expiration          = 5,
        enable_implicit_grant     = true,
      },
    })

    local consumer = bp.consumers:insert {
      username = "bob",
    }
    assert(dao.oauth2_credentials:insert {
      client_id     = "clientid123",
      client_secret = "secret123",
      redirect_uri  = "http://google.com/kong",
      name          = "testapp",
      consumer_id   = consumer.id,
    })

    assert(helpers.start_kong({
      database = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
    admin_client     = helpers.admin_client()
    proxy_ssl_client = helpers.proxy_ssl_client()
  end)

  after_each(function()
    if admin_client and proxy_ssl_client then
      admin_client:close()
      proxy_ssl_client:close()
    end
    helpers.stop_kong()
  end)

  local function provision_code(client_id)
    local res = assert(proxy_ssl_client:send {
      method = "POST",
      path = "/oauth2/authorize",
      body = {
        provision_key = "provision123",
        client_id = client_id,
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
    local raw_body = res:read_body()
    local body = cjson.decode(raw_body)
    if body.redirect_uri then
      local iterator, err = ngx.re.gmatch(body.redirect_uri, "^http://google\\.com/kong\\?code=([\\w]{32,32})&state=hello$")
      assert.is_nil(err)
      local m, err = iterator()
      assert.is_nil(err)
      return m[1]
    end
  end

  describe("OAuth2 Credentials entity invalidation", function()
    it("should invalidate when OAuth2 Credential entity is deleted", function()
      -- It should properly work
      local code = provision_code("clientid123")
      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/oauth2/token",
        body = { code = code, client_id = "clientid123", client_secret = "secret123", grant_type = "authorization_code" },
        headers = {
          ["Host"] = "oauth2.com",
          ["Content-Type"] = "application/json"
        }
      })
      assert.response(res).has.status(200)

      -- Check that cache is populated
      local cache_key = dao.oauth2_credentials:cache_key("clientid123")

      local res = assert(admin_client:send {
        method = "GET",
        path = "/cache/" .. cache_key,
        headers = {},
        query = { cache = "lua" },
      })
      assert.response(res).has.status(200)
      local credential = assert.response(res).has.jsonbody()

      -- Delete OAuth2 credential (which triggers invalidation)
      local res = assert(admin_client:send {
        method = "DELETE",
        path = "/consumers/bob/oauth2/" .. credential.id,
        headers = {}
      })
      assert.response(res).has.status(204)

      -- ensure cache is invalidated
      helpers.wait_until(function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/cache/" .. cache_key
        })
        res:read_body()
        return res.status == 404
      end, 5)

      -- It should not work
      local code = provision_code("clientid123")
      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/oauth2/token",
        body = { code = code, client_id = "clientid123", client_secret = "secret123", grant_type = "authorization_code" },
        headers = {
          ["Host"] = "oauth2.com",
          ["Content-Type"] = "application/json"
        }
      })
      assert.response(res).has.status(400)
    end)

    it("should invalidate when OAuth2 Credential entity is updated", function()
      -- It should properly work
      local code = provision_code("clientid123")
      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/oauth2/token",
        body = { code = code, client_id = "clientid123", client_secret = "secret123", grant_type = "authorization_code" },
        headers = {
          ["Host"] = "oauth2.com",
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(200, res)

      -- It should not work
      local code = provision_code("updated_clientid123")
      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/oauth2/token",
        body = { code = code, client_id = "clientid123", client_secret = "secret123", grant_type = "authorization_code" },
        headers = {
          ["Host"] = "oauth2.com",
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(400, res)

      -- Check that cache is populated
      local cache_key = dao.oauth2_credentials:cache_key("clientid123")

      local res = assert(admin_client:send {
        method = "GET",
        path = "/cache/" .. cache_key,
        headers = {}
      })
      local credential = cjson.decode(assert.res_status(200, res))

      -- Update OAuth2 credential (which triggers invalidation)
      local res = assert(admin_client:send {
        method = "PATCH",
        path = "/consumers/bob/oauth2/" .. credential.id,
        body = {
          client_id = "updated_clientid123"
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(200, res)

      -- ensure cache is invalidated
      helpers.wait_until(function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/cache/" .. cache_key
        })
        res:read_body()
        return res.status == 404
      end, 5)

      -- It should work
      local code = provision_code("updated_clientid123")
      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/oauth2/token",
        body = { code = code, client_id = "updated_clientid123", client_secret = "secret123", grant_type = "authorization_code" },
        headers = {
          ["Host"] = "oauth2.com",
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(200, res)

      -- It should not work
      local code = provision_code("clientid123")
      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/oauth2/token",
        body = { code = code, client_id = "clientid123", client_secret = "secret123", grant_type = "authorization_code" },
        headers = {
          ["Host"] = "oauth2.com",
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(400, res)
    end)
  end)

  describe("Consumer entity invalidation", function()
    it("should invalidate when Consumer entity is deleted", function()
      -- It should properly work
      local code = provision_code("clientid123")
      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/oauth2/token",
        body = { code = code, client_id = "clientid123", client_secret = "secret123", grant_type = "authorization_code" },
        headers = {
          ["Host"] = "oauth2.com",
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(200, res)

      -- Check that cache is populated
      local cache_key = dao.oauth2_credentials:cache_key("clientid123")

      local res = assert(admin_client:send {
        method = "GET",
        path = "/cache/" .. cache_key,
        headers = {}
      })
      assert.res_status(200, res)

      -- Delete Consumer (which triggers invalidation)
      local res = assert(admin_client:send {
        method = "DELETE",
        path = "/consumers/bob",
        headers = {}
      })
      assert.res_status(204, res)

      -- ensure cache is invalidated
      helpers.wait_until(function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/cache/" .. cache_key
        })
        res:read_body()
        return res.status == 404
      end, 5)

      -- It should not work
      local code = provision_code("clientid123")
      local res = assert(proxy_ssl_client:send {
        method = "POST",
        path = "/oauth2/token",
        body = { code = code, client_id = "clientid123", client_secret = "secret123", grant_type = "authorization_code" },
        headers = {
          ["Host"] = "oauth2.com",
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(400, res)
    end)
  end)

  describe("OAuth2 access token entity invalidation", function()
    it("should invalidate when OAuth2 token entity is deleted", function()
      -- It should properly work
      local code = provision_code("clientid123")
      local res = assert(proxy_ssl_client:send {
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

      -- The token should work
      local res = assert(proxy_ssl_client:send {
        method = "GET",
        path = "/status/200?access_token=" .. token.access_token,
        headers = {
          ["Host"] = "oauth2.com"
        }
      })
      assert.res_status(200, res)

      -- Check that cache is populated
      local cache_key = dao.oauth2_tokens:cache_key(token.access_token)
      local res = assert(admin_client:send {
        method = "GET",
        path = "/cache/" .. cache_key,
        headers = {}
      })
      assert.res_status(200, res)

      local res = dao.oauth2_tokens:find_all({access_token=token.access_token})
      local token_id = res[1].id
      assert.is_string(token_id)

      -- Delete token (which triggers invalidation)
      local res = assert(admin_client:send {
        method = "DELETE",
        path = "/oauth2_tokens/" .. token_id,
        headers = {}
      })
      assert.res_status(204, res)

      -- ensure cache is invalidated
      helpers.wait_until(function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/cache/" .. cache_key
        })
        res:read_body()
        return res.status == 404
      end, 5)

      -- It should not work
      local res = assert(proxy_ssl_client:send {
        method = "GET",
        path = "/status/200?access_token=" .. token.access_token,
        headers = {
          ["Host"] = "oauth2.com"
        }
      })
      assert.res_status(401, res)
    end)

    it("should invalidate when Oauth2 token entity is updated", function()
      -- It should properly work
      local code = provision_code("clientid123")
      local res = assert(proxy_ssl_client:send {
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

      -- The token should work
      local res = assert(proxy_ssl_client:send {
        method = "GET",
        path = "/status/200?access_token=" .. token.access_token,
        headers = {
          ["Host"] = "oauth2.com"
        }
      })
      assert.res_status(200, res)

      -- Check that cache is populated
      local cache_key = dao.oauth2_tokens:cache_key(token.access_token)

      local res = assert(admin_client:send {
        method = "GET",
        path = "/cache/" .. cache_key,
        headers = {}
      })
      assert.res_status(200, res)

      local res = dao.oauth2_tokens:find_all({access_token=token.access_token})
      local token_id = res[1].id
      assert.is_string(token_id)

      -- Update OAuth 2 token (which triggers invalidation)
      local res = assert(admin_client:send {
        method = "PATCH",
        path = "/oauth2_tokens/" .. token_id,
        body = {
          access_token = "updated_token"
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(200, res)

      -- ensure cache is invalidated
      helpers.wait_until(function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/cache/" .. cache_key
        })
        res:read_body()
        return res.status == 404
      end, 5)

      -- It should work
      local res = assert(proxy_ssl_client:send {
        method = "GET",
        path = "/status/200?access_token=updated_token",
        headers = {
          ["Host"] = "oauth2.com"
        }
      })
      assert.res_status(200, res)

      -- It should not work
      local res = assert(proxy_ssl_client:send {
        method = "GET",
        path = "/status/200?access_token=" .. token.access_token,
        headers = {
          ["Host"] = "oauth2.com"
        }
      })
      assert.res_status(401, res)
    end)
  end)

  describe("OAuth2 client entity invalidation", function()
    it("should invalidate token when OAuth2 client entity is deleted", function()
      -- It should properly work
      local code = provision_code("clientid123")
      local res = assert(proxy_ssl_client:send {
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

      -- The token should work
      local res = assert(proxy_ssl_client:send {
        method = "GET",
        path = "/status/200?access_token=" .. token.access_token,
        headers = {
          ["Host"] = "oauth2.com"
        }
      })
      assert.res_status(200, res)

      -- Check that cache is populated
      local cache_key = dao.oauth2_tokens:cache_key(token.access_token)

      local res = assert(admin_client:send {
        method = "GET",
        path = "/cache/" .. cache_key,
        headers = {}
      })
      assert.res_status(200, res)

      -- Retrieve credential ID
      local cache_key_credential = dao.oauth2_credentials:cache_key("clientid123")

      local res = assert(admin_client:send {
        method = "GET",
        path = "/cache/" .. cache_key_credential,
        headers = {}
      })
      local credential = cjson.decode(assert.res_status(200, res))

      -- Delete OAuth2 client (which triggers invalidation)
      local res = assert(admin_client:send {
        method = "DELETE",
        path = "/consumers/bob/oauth2/" .. credential.id,
        headers = {}
      })
      assert.res_status(204, res)

      -- ensure cache is invalidated
      helpers.wait_until(function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/cache/" .. cache_key
        })
        res:read_body()
        return res.status == 404
      end, 5)

      -- it should not work
      local res = assert(proxy_ssl_client:send {
        method = "GET",
        path = "/status/200?access_token=" .. token.access_token,
        headers = {
          ["Host"] = "oauth2.com"
        }
      })
      assert.res_status(401, res)
    end)
  end)

end)
end
