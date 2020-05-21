local helpers = require "spec.helpers"
local cjson   = require "cjson"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: key-auth (invalidations) [#" .. strategy .. "]", function()
    local admin_client, proxy_client
    local db

    before_each(function()
      local bp
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "keyauth_credentials",
      })

      local route = bp.routes:insert {
        hosts = { "key-auth.com" },
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route.id },
      }

      local consumer = bp.consumers:insert {
        username = "bob",
      }

      bp.keyauth_credentials:insert {
        key      = "kong",
        consumer = { id = consumer.id },
      }

      assert(helpers.start_kong({
        database   = strategy,
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
        method  = "GET",
        path    = "/",
        headers = {
          ["Host"]   = "key-auth.com",
          ["apikey"] = "kong"
        }
      })
      assert.res_status(200, res)

      -- ensure cache is populated
      local cache_key = db.keyauth_credentials:cache_key("kong")
      res = assert(admin_client:send {
        method = "GET",
        path   = "/cache/" .. cache_key
      })
      assert.res_status(200, res)

      -- delete Consumer entity
      res = assert(admin_client:send {
        method = "DELETE",
        path   = "/consumers/bob"
      })
      assert.res_status(204, res)

      -- ensure cache is invalidated
      helpers.wait_for_invalidation(cache_key)

      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Host"]   = "key-auth.com",
          ["apikey"] = "kong"
        }
      })
      assert.res_status(401, res)
    end)

    it("invalidates credentials from cache when deleted", function()
      -- populate cache
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Host"]   = "key-auth.com",
          ["apikey"] = "kong"
        }
      })
      assert.res_status(200, res)

      -- ensure cache is populated
      local cache_key = db.keyauth_credentials:cache_key("kong")
      res = assert(admin_client:send {
        method = "GET",
        path   = "/cache/" .. cache_key
      })
      local body = assert.res_status(200, res)
      local credential = cjson.decode(body)

      -- delete credential entity
      res = assert(admin_client:send {
        method = "DELETE",
        path   = "/consumers/bob/key-auth/" .. credential.id
      })
      assert.res_status(204, res)

      -- ensure cache is invalidated
      helpers.wait_for_invalidation(cache_key)

      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Host"]   = "key-auth.com",
          ["apikey"] = "kong"
        }
      })
      assert.res_status(401, res)
    end)

    it("invalidated credentials from cache when updated", function()
      -- populate cache
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Host"]   = "key-auth.com",
          ["apikey"] = "kong"
        }
      })
      assert.res_status(200, res)

      -- ensure cache is populated
      local cache_key = db.keyauth_credentials:cache_key("kong")
      res = assert(admin_client:send {
        method = "GET",
        path   = "/cache/" .. cache_key
      })
      local body = assert.res_status(200, res)
      local credential = cjson.decode(body)

      -- delete credential entity
      res = assert(admin_client:send {
        method  = "PATCH",
        path    = "/consumers/bob/key-auth/" .. credential.id,
        body    = {
          key   = "kong-updated"
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(200, res)

      -- ensure cache is invalidated
      helpers.wait_for_invalidation(cache_key)

      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Host"]   = "key-auth.com",
          ["apikey"] = "kong"
        }
      })
      assert.res_status(401, res)

      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Host"]   = "key-auth.com",
          ["apikey"] = "kong-updated"
        }
      })
      assert.res_status(200, res)
    end)
  end)
end
