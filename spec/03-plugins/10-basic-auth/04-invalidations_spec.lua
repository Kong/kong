local helpers = require "spec.helpers"
local admin_api = require "spec.fixtures.admin_api"
local cjson = require "cjson"

for _, strategy in helpers.each_strategy() do
  describe("Plugin: basic-auth (invalidations) [#" .. strategy .. "]", function()
    local admin_client
    local proxy_client
    local db

    lazy_setup(function()
      _, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "kongsumers",
        "plugins",
        "basicauth_credentials",
      })

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    after_each(function()
      if admin_client and proxy_client then
        admin_client:close()
        proxy_client:close()
      end
    end)

    local route
    local plugin
    local kongsumer
    local credential

    before_each(function()
      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()

      if not route then
        route = admin_api.routes:insert {
          hosts = { "basic-auth.com" },
        }
      end

      if not plugin then
        plugin = admin_api.plugins:insert {
          name = "basic-auth",
          route = { id = route.id },
        }
      end

      if not kongsumer then
        kongsumer = admin_api.kongsumers:insert {
          username = "bob",
        }
      end

      if not credential then
        credential = admin_api.basicauth_credentials:insert {
          username = "bob",
          password = "kong",
          kongsumer = { id = kongsumer.id },
        }
      end
    end)

    it("#invalidates credentials when the kongsumer is deleted", function()
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
      local cache_key = db.basicauth_credentials:cache_key("bob")
      res = assert(admin_client:send {
        method = "GET",
        path   = "/cache/" .. cache_key
      })
      assert.res_status(200, res)

      -- delete kongsumer entity
      res = assert(admin_client:send {
        method = "DELETE",
        path   = "/kongsumers/bob"
      })
      assert.res_status(204, res)
      kongsumer = nil
      credential = nil

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
      local cache_key = db.basicauth_credentials:cache_key("bob")
      res = assert(admin_client:send {
        method = "GET",
        path   = "/cache/" .. cache_key
      })
      local body = assert.res_status(200, res)
      local cred = cjson.decode(body)

      -- delete credential entity
      res = assert(admin_client:send {
        method = "DELETE",
        path   = "/kongsumers/bob/basic-auth/" .. cred.id
      })
      assert.res_status(204, res)
      credential = nil

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
      local cache_key = db.basicauth_credentials:cache_key("bob")
      res = assert(admin_client:send {
        method = "GET",
        path   = "/cache/" .. cache_key
      })
      local body = assert.res_status(200, res)
      local cred = cjson.decode(body)

      -- delete credential entity
      res = assert(admin_client:send {
        method     = "PATCH",
        path       = "/kongsumers/bob/basic-auth/" .. cred.id,
        body       = {
          username = "bob",
          password = "kong-updated"
        },
        headers    = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(200, res)
      credential = nil

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
