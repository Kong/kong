local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Plugin: key-auth (invalidations)", function()
  local admin_client, proxy_client
  local dao
  local bp
  local _

  before_each(function()
    bp, _, dao = helpers.get_db_utils()

    local api = assert(dao.apis:insert {
      name         = "api-1",
      hosts        = { "key-auth.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(dao.plugins:insert {
      name   = "key-auth",
      api_id = api.id,
    })

    local consumer = bp.consumers:insert {
      username = "bob",
    }
    assert(dao.keyauth_credentials:insert {
      key         = "kong",
      consumer_id = consumer.id,
    })

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
    proxy_client = helpers.proxy_client()
    admin_client = helpers.admin_client()
  end)

  after_each(function()
    if admin_client and proxy_client then
      admin_client:close()
      proxy_client:close()
    end
    helpers.stop_kong()
  end)

  it("invalidates credentials when the Consumer is deleted", function()
    -- populate cache
    local res = assert(proxy_client:send {
      method = "GET",
      path = "/",
      headers = {
        ["Host"] = "key-auth.com",
        ["apikey"] = "kong"
      }
    })
    assert.res_status(200, res)

    -- ensure cache is populated
    local cache_key = dao.keyauth_credentials:cache_key("kong")
    res = assert(admin_client:send {
      method = "GET",
      path = "/cache/" .. cache_key
    })
    assert.res_status(200, res)

    -- delete Consumer entity
    res = assert(admin_client:send {
      method = "DELETE",
      path = "/consumers/bob"
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
    end)

    res = assert(proxy_client:send {
      method = "GET",
      path = "/",
      headers = {
        ["Host"] = "key-auth.com",
        ["apikey"] = "kong"
      }
    })
    assert.res_status(403, res)
  end)

  it("invalidates credentials from cache when deleted", function()
    -- populate cache
    local res = assert(proxy_client:send {
      method = "GET",
      path = "/",
      headers = {
        ["Host"] = "key-auth.com",
        ["apikey"] = "kong"
      }
    })
    assert.res_status(200, res)

    -- ensure cache is populated
    local cache_key = dao.keyauth_credentials:cache_key("kong")
    res = assert(admin_client:send {
      method = "GET",
      path = "/cache/" .. cache_key
    })
    local body = assert.res_status(200, res)
    local credential = cjson.decode(body)

    -- delete credential entity
    res = assert(admin_client:send {
      method = "DELETE",
      path = "/consumers/bob/key-auth/" .. credential.id
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
    end)

    res = assert(proxy_client:send {
      method = "GET",
      path = "/",
      headers = {
        ["Host"] = "key-auth.com",
        ["apikey"] = "kong"
      }
    })
    assert.res_status(403, res)
  end)

  it("invalidated credentials from cache when updated", function()
    -- populate cache
    local res = assert(proxy_client:send {
      method = "GET",
      path = "/",
      headers = {
        ["Host"] = "key-auth.com",
        ["apikey"] = "kong"
      }
    })
    assert.res_status(200, res)

    -- ensure cache is populated
    local cache_key = dao.keyauth_credentials:cache_key("kong")
    res = assert(admin_client:send {
      method = "GET",
      path = "/cache/" .. cache_key
    })
    local body = assert.res_status(200, res)
    local credential = cjson.decode(body)

    -- delete credential entity
    res = assert(admin_client:send {
      method = "PATCH",
      path = "/consumers/bob/key-auth/" .. credential.id,
      body = {
        key = "kong-updated"
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
    end)

    res = assert(proxy_client:send {
      method = "GET",
      path = "/",
      headers = {
        ["Host"] = "key-auth.com",
        ["apikey"] = "kong"
      }
    })
    assert.res_status(403, res)

    res = assert(proxy_client:send {
      method = "GET",
      path = "/",
      headers = {
        ["Host"] = "key-auth.com",
        ["apikey"] = "kong-updated"
      }
    })
    assert.res_status(200, res)
  end)
end)
