local helpers = require "spec.helpers"
local strategies = require("kong.plugins.gql-proxy-cache.strategies")
local cjson   = require "cjson"

local TIMEOUT = 10 -- default timeout for non-memory strategies

for _, policy in ipairs({"memory"}) do
  describe("gql-proxy-cache access with policy: #" .. policy, function()
    local client, admin_client
    local policy_config

    if policy == "memory" then
      policy_config = {
        dictionary_name = "kong",
      }
    end

    local strategy = strategies({
      strategy_name = policy,
      strategy_opts = policy_config,
    })

    -- These wait functions use the plugin API to retrieve the cache entry
    -- and expose it to the function passed.
    -- Trying to access the strategy:fetch works for redis, but not for the
    -- in memory cache.
    local function wait_until_key(key, func)
      helpers.wait_until(function()
        local res = admin_client:send {
          method = "GET",
          path   = "/gql-proxy-cache/" .. key
        }
        -- wait_until does not like asserts
        if not res then return false end

        local body = res:read_body()

        return func(res, body)
      end, TIMEOUT)
    end

    -- wait until key is in cache (we get a 200 on plugin API) and execute
    -- a test function if provided.
    local function wait_until_key_in_cache(key, func)
      local func = func or function(obj) return true end
      wait_until_key(key, function(res, body)
        if res.status == 200 then
          local obj = cjson.decode(body)
          return func(obj)
        end

        return false
      end)
    end

    local function wait_until_key_not_in_cache(key)
      wait_until_key(key, function(res)
        -- API endpoint returns either 200, 500 or 404
        return res.status > 200
      end)
    end

    setup(function()

      local bp = helpers.get_db_utils(nil, nil, {"gql-proxy-cache"})
      strategy:flush(true)

      local route1 = assert(bp.routes:insert {
        hosts = { "route-1.com" },
      })

      local route2 = assert(bp.routes:insert {
        hosts = { "route-2.com" },
      })

      local route3 = assert(bp.routes:insert {
        hosts = { "route-3.com" },
      })

      local route4 = assert(bp.routes:insert {
        hosts = { "route-4.com" },
      })

      local route5 = assert(bp.routes:insert {
        hosts = { "route-5.com" },
      })

      assert(bp.plugins:insert {
        name = "gql-proxy-cache",
        route = { id = route1.id },
        config = {
          strategy = policy,
          [policy] = policy_config,
        },
      })

      assert(bp.plugins:insert {
        name = "gql-proxy-cache",
        route = { id = route2.id },
        config = {
          strategy = policy,
          cache_ttl = 2,
          [policy] = policy_config,
        },
      })

      assert(bp.plugins:insert {
        name = "gql-proxy-cache",
        route = { id = route3.id },
        config = {
          strategy = policy,
          cache_ttl = 2,
          [policy] = policy_config,
        },
      })

      assert(bp.plugins:insert {
        name = "gql-proxy-cache",
        route = { id = route4.id },
        config = {
          strategy = policy,
          [policy] = policy_config,
        },
      })

      assert(bp.plugins:insert {
        name = "gql-proxy-cache",
        route = { id = route5.id },
        config = {
          strategy = policy,
          [policy] = policy_config,
        },
      })

      assert(helpers.start_kong({
        plugins = "bundled,gql-proxy-cache",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    before_each(function()
      if client then
        client:close()
      end
      if admin_client then
        admin_client:close()
      end
      client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    teardown(function()
      if client then
        client:close()
      end

      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong(nil, true)
    end)

    it("caches a simple request", function()
      local res = assert(client:send {
        method = "POST",
        path = "/request",
        headers = {
          host = "route-1.com",
        },
        body = '{ query { user(id:"1") { id, name }}}'
      })

      local body1 = assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      -- cache key is an md5sum of the prefix uuid, method, and $request
      local cache_key1 = res.headers["X-Cache-Key"]
      assert.matches("^[%w%d]+$", cache_key1)
      assert.equals(32, #cache_key1)

      wait_until_key_in_cache(cache_key1)
      --
      local res = client:send {
        method = "POST",
        path = "/request",
        headers = {
          host = "route-1.com",
        },
        body = '{ query { user(id:"1") { id, name }}}'
      }

      local body2 = assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])
      local cache_key2 = res.headers["X-Cache-Key"]
      assert.same(cache_key1, cache_key2)

      -- assert that response bodies are identical
      assert.same(body1, body2)
    end)

    it("differentiate two same structure queries with different filter parameters", function()
      local res = assert(client:send {
        method = "POST",
        path = "/request",
        headers = {
          host = "route-4.com",
        },
        body = '{ query { user(id:"1") { id, name }}}'
      })

      local body1 = assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      -- cache key is an md5sum of the prefix uuid, method, and $request
      local cache_key1 = res.headers["X-Cache-Key"]
      assert.matches("^[%w%d]+$", cache_key1)
      assert.equals(32, #cache_key1)

      wait_until_key_in_cache(cache_key1)
      --
      local res = client:send {
        method = "POST",
        path = "/request",
        headers = {
          host = "route-4.com",
        },
        body = '{ query { user(id:"1") { id, name }}}'
      }

      local body2 = assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])
      local cache_key2 = res.headers["X-Cache-Key"]
      assert.same(cache_key1, cache_key2)

      -- assert that response bodies are identical
      assert.same(body1, body2)

      local res = assert(client:send {
        method = "POST",
        path = "/request",
        headers = {
          host = "route-4.com",
        },
        body = '{ query { user(id:"1-2") { id, name }}}'
      })

      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])
    end)

    it("differentiate two same queries with extra node parameter", function()
      local res = assert(client:send {
        method = "POST",
        path = "/request",
        headers = {
          host = "route-5.com",
        },
        body = '{ query { user(id:"5") { id, name }}}'
      })

      local body1 = assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      -- cache key is an md5sum of the prefix uuid, method, and $request
      local cache_key1 = res.headers["X-Cache-Key"]
      assert.matches("^[%w%d]+$", cache_key1)
      assert.equals(32, #cache_key1)

      wait_until_key_in_cache(cache_key1)
      --
      local res = client:send {
        method = "POST",
        path = "/request",
        headers = {
          host = "route-5.com",
        },
        body = '{ query { user(id:"5") { id, name }}}'
      }

      local body2 = assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])
      local cache_key2 = res.headers["X-Cache-Key"]
      assert.same(cache_key1, cache_key2)

      -- assert that response bodies are identical
      assert.same(body1, body2)

      local res = assert(client:send {
        method = "POST",
        path = "/request",
        headers = {
          host = "route-5.com",
        },
        body = '{ query { user(id:"5") { id, name, surname }}}'
      })

      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])
    end)

    it("respects cache ttl", function()
      local res = assert(client:send {
        method = "POST",
        path = "/request",
        headers = {
          host = "route-2.com",
        },
        body = '{ query { user(id:"2") { id, name }}}'
      })

      local cache_key2 = res.headers["X-Cache-Key"]
      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      wait_until_key_in_cache(cache_key2)

      res = client:send {
        method = "POST",
        path = "/request",
        headers = {
          host = "route-2.com",
        },
        body = '{ query { user(id:"2") { id, name }}}'
      }

      assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])
      local cache_key = res.headers["X-Cache-Key"]

      -- wait until the strategy expires the object for the given
      -- cache key
      wait_until_key_not_in_cache(cache_key)

      -- and go through the cycle again
      res = assert(client:send {
        method = "POST",
        path = "/request",
        headers = {
          host = "route-2.com",
        },
        body = '{ query { user(id:"2") { id, name }}}'
      })

      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])
      cache_key = res.headers["X-Cache-Key"]

      -- wait until the underlying strategy converges
      wait_until_key_in_cache(cache_key)

      res = assert(client:send {
        method = "POST",
        path = "/request",
        headers = {
          host = "route-2.com",
        },
        body = '{ query { user(id:"2") { id, name }}}'
      })

      assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])
    end)
  end)
end
