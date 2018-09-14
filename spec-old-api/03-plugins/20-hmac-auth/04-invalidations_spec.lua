local helpers = require "spec.helpers"
local cjson = require "cjson"

local openssl_hmac = require "openssl.hmac"

describe("Plugin: hmac-auth (invalidations)", function()
  local client_proxy, client_admin, consumer, credential
  local dao
  local bp
  local db

  setup(function()
    bp, db, dao = helpers.get_db_utils()

    local api = assert(dao.apis:insert {
      name         = "api-1",
      hosts        = { "hmacauth.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(db.plugins:insert {
      name   = "hmac-auth",
      api = { id = api.id },
      config = {
        clock_skew = 3000,
      },
    })

    consumer = bp.consumers:insert {
      username  = "consumer1",
      custom_id = "1234",
    }
    credential = bp.hmacauth_credentials:insert({
      username = "bob",
      secret   = "secret",
      consumer = { id = consumer.id },
    })

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
    client_proxy = helpers.proxy_client()
    client_admin = helpers.admin_client()
  end)

   teardown(function()
    if client_proxy and client_admin then
      client_proxy:close()
      client_admin:close()
    end
    helpers.stop_kong(nil, true)
  end)

  local function hmac_sha1_binary(secret, data)
    return openssl_hmac.new(secret, "sha1"):final(data)
  end

  local function get_authorization(username)
    local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
    local encodedSignature   = ngx.encode_base64(hmac_sha1_binary("secret", "date: " .. date))
    return [["hmac username="]] .. username
         .. [[",algorithm="hmac-sha1",headers="date",signature="]]
         .. encodedSignature .. [["]], date
  end

  describe("HMAC Auth Credentials entity invalidation", function()
    it("should invalidate when Hmac Auth Credential entity is deleted", function()
      -- It should work
      local authorization, date = get_authorization("bob")
      local res = assert(client_proxy:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          authorization = authorization
        }
      })
      assert.res_status(200, res)

      -- Check that cache is populated
      local cache_key = db.hmacauth_credentials:cache_key("bob")
      res = assert(client_admin:send {
        method = "GET",
        path = "/cache/" .. cache_key,
        body = {},
      })
      assert.res_status(200, res)

      -- Retrieve credential ID
      res = assert(client_admin:send {
        method = "GET",
        path = "/consumers/consumer1/hmac-auth/",
        body = {},
      })
      local body = assert.res_status(200, res)
      local credential_id = cjson.decode(body).data[1].id
      assert.equal(credential.id, credential_id)

      -- Delete Hmac Auth credential (which triggers invalidation)
      res = assert(client_admin:send {
        method = "DELETE",
        path = "/consumers/consumer1/hmac-auth/" .. credential_id,
        body = {},
      })
      assert.res_status(204, res)

      -- ensure cache is invalidated
      helpers.wait_until(function()
        local res = assert(client_admin:send {
          method = "GET",
          path = "/cache/" .. cache_key
        })
        res:read_body()
        return res.status == 404
      end)

      -- It should not work
      authorization, date = get_authorization("bob")
      local res = assert(client_proxy:send {
        method = "POST",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          authorization = authorization
        }
      })
      assert.res_status(403, res)
    end)
    it("should invalidate when Hmac Auth Credential entity is updated", function()
      local res = assert(client_admin:send {
        method = "POST",
        path = "/consumers/consumer1/hmac-auth",
        body = {
          username = "bob",
          secret   = "secret",
          consumer = { id = consumer.id },
        },
        headers = {
          ["Content-Type"] = "application/json",
        }
      })
      local body = assert.res_status(201, res)
      credential = cjson.decode(body)

      -- It should work
      local authorization, date = get_authorization("bob")
      local res = assert(client_proxy:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          authorization = authorization
        }
      })
      assert.res_status(200, res)

      -- It should not work
      local authorization, date = get_authorization("hello123")
      res = assert(client_proxy:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          authorization = authorization
        }
      })
      assert.res_status(403, res)

      -- Update Hmac Auth credential (which triggers invalidation)
      res = assert(client_admin:send {
        method = "PATCH",
        path = "/consumers/consumer1/hmac-auth/" .. credential.id,
        body = {
          username = "hello123"
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(200, res)

      -- ensure cache is invalidated
      local cache_key = db.hmacauth_credentials:cache_key("bob")
      helpers.wait_until(function()
        local res = assert(client_admin:send {
          method = "GET",
          path = "/cache/" .. cache_key
        })
        res:read_body()
        return res.status == 404
      end)

      -- It should work
      local authorization, date = get_authorization("hello123")
      local res = assert(client_proxy:send {
        method = "GET",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          authorization = authorization
        }
      })
      assert.res_status(200, res)
    end)
  end)
  describe("Consumer entity invalidation", function()
    it("should invalidate when Consumer entity is deleted", function()
      -- It should work
      local authorization, date = get_authorization("hello123")
      local res = assert(client_proxy:send {
        method = "GET",
        path = "/requests",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          authorization = authorization
        }
      })
      assert.res_status(200, res)

      -- Check that cache is populated
      local cache_key = db.hmacauth_credentials:cache_key("hello123")
      res = assert(client_admin:send {
        method = "GET",
        path = "/cache/" .. cache_key,
        body = {},
      })
      assert.res_status(200, res)

      -- Delete Consumer (which triggers invalidation)
      res = assert(client_admin:send {
        method = "DELETE",
        path = "/consumers/consumer1",
        body = {},
      })
      assert.res_status(204, res)

     -- ensure cache is invalidated
      helpers.wait_until(function()
        local res = assert(client_admin:send {
          method = "GET",
          path = "/cache/" .. cache_key
        })
        res:read_body()
        return res.status == 404
      end)

      -- It should not work
      local authorization, date = get_authorization("bob")
      local res = assert(client_proxy:send {
        method = "GET",
        body = {},
        headers = {
          ["HOST"] = "hmacauth.com",
          date = date,
          authorization = authorization
        }
      })
      assert.res_status(403, res)
    end)
  end)
end)
