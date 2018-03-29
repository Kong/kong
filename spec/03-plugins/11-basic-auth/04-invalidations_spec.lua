local helpers = require "spec.helpers"
local cjson = require "cjson"

for _, strategy in helpers.each_strategy() do
  describe("Plugin: basic-auth (invalidations) [#" .. strategy .. "]", function()
    local admin_client
    local proxy_client
    local db
    local dao
    local bp

    setup(function()
      bp, db, dao = helpers.get_db_utils(strategy)
    end)

    before_each(function()
      assert(db:truncate())
      dao:truncate_tables()

      local route = bp.routes:insert {
        hosts = { "basic-auth.com" },
      }

      bp.plugins:insert {
        name     = "basic-auth",
        route_id = route.id,
      }

      local consumer = bp.consumers:insert {
        username = "bob",
      }

      assert(dao.basicauth_credentials:insert {
        username    = "bob",
        password    = "kong",
        consumer_id = consumer.id,
      })

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
          ["Authorization"] = "Basic Ym9iOmtvbmc=",
          ["Host"]          = "basic-auth.com"
        }
      })
      assert.res_status(200, res)

      -- ensure cache is populated
      local cache_key = dao.basicauth_credentials:cache_key("bob")
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
      helpers.wait_until(function()
        local res = assert(admin_client:send {
          method  = "GET",
          path    = "/cache/" .. cache_key
        })
        res:read_body()
        return res.status == 404
      end)

      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Authorization"] = "Basic Ym9iOmtvbmc=",
          ["Host"]          = "basic-auth.com"
        }
      })
      assert.res_status(403, res)
    end)

    it("invalidates credentials from cache when deleted", function()
      -- populate cache
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Authorization"] = "Basic Ym9iOmtvbmc=",
          ["Host"]          = "basic-auth.com"
        }
      })
      assert.res_status(200, res)

      -- ensure cache is populated
      local cache_key = dao.basicauth_credentials:cache_key("bob")
      res = assert(admin_client:send {
        method = "GET",
        path   = "/cache/" .. cache_key
      })
      local body = assert.res_status(200, res)
      local credential = cjson.decode(body)

      -- delete credential entity
      res = assert(admin_client:send {
        method = "DELETE",
        path   = "/consumers/bob/basic-auth/" .. credential.id
      })
      assert.res_status(204, res)

      -- ensure cache is invalidated
      helpers.wait_until(function()
        local res = assert(admin_client:send {
          method = "GET",
          path   = "/cache/" .. cache_key
        })
        res:read_body()
        return res.status == 404
      end)

      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Authorization"] = "Basic Ym9iOmtvbmc=",
          ["Host"]          = "basic-auth.com"
        }
      })
      assert.res_status(403, res)
    end)

    it("invalidated credentials from cache when updated", function()
      -- populate cache
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Authorization"] = "Basic Ym9iOmtvbmc=",
          ["Host"]          = "basic-auth.com"
        }
      })
      assert.res_status(200, res)

      -- ensure cache is populated
      local cache_key = dao.basicauth_credentials:cache_key("bob")
      res = assert(admin_client:send {
        method = "GET",
        path   = "/cache/" .. cache_key
      })
      local body = assert.res_status(200, res)
      local credential = cjson.decode(body)

      -- delete credential entity
      res = assert(admin_client:send {
        method     = "PATCH",
        path       = "/consumers/bob/basic-auth/" .. credential.id,
        body       = {
          username = "bob",
          password = "kong-updated"
        },
        headers    = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(200, res)

      -- ensure cache is invalidated
      helpers.wait_until(function()
        local res = assert(admin_client:send {
          method  = "GET",
          path    = "/cache/" .. cache_key
        })
        res:read_body()
        return res.status == 404
      end)

      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Authorization"] = "Basic Ym9iOmtvbmc=",
          ["Host"]          = "basic-auth.com"
        }
      })
      assert.res_status(403, res)

      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Authorization"] = "Basic Ym9iOmtvbmctdXBkYXRlZA==",
          ["Host"]          = "basic-auth.com"
        }
      })
      assert.res_status(200, res)
    end)
  end)
end
