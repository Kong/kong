local helpers = require "spec.helpers"



local POLL_INTERVAL = 0.3

local function get(client, host)
  return assert(client:get("/get", {
    headers = {
      Host = host,
      ["kong-debug"] = 1,
    },
  }))
end

for _, strategy in helpers.each_strategy() do
describe("proxy-cache invalidations via: " .. strategy, function()

  local client_1
  local client_2
  local admin_client_1
  local admin_client_2
  local route1
  local route2
  local plugin1
  local plugin2
  local bp

  setup(function()
    bp = helpers.get_db_utils(strategy, nil, {"proxy-cache"})

    route1 = assert(bp.routes:insert {
      hosts = { "route-1.test" },
    })

    route2 = assert(bp.routes:insert {
      hosts = { "route-2.test" },
    })

    plugin1 = assert(bp.plugins:insert {
      name = "proxy-cache",
      route = { id = route1.id },
      config = {
        strategy = "memory",
        content_type = { "text/plain", "application/json" },
        memory = {
          dictionary_name = "kong",
        },
      },
    })

    plugin2 = assert(bp.plugins:insert {
      name = "proxy-cache",
      route = { id = route2.id },
      config = {
        strategy = "memory",
        content_type = { "text/plain", "application/json" },
        memory = {
          dictionary_name = "kong",
        },
      },
    })


    assert(helpers.start_kong {
      log_level             = "debug",
      prefix                = "servroot1",
      database              = strategy,
      proxy_listen          = "0.0.0.0:8000",
      proxy_listen_ssl      = "0.0.0.0:8443",
      admin_listen          = "0.0.0.0:8001",
      admin_gui_listen      = "0.0.0.0:8002",
      admin_ssl             = false,
      admin_gui_ssl         = false,
      db_update_frequency   = POLL_INTERVAL,
      plugins               = "proxy-cache",
      nginx_conf            = "spec/fixtures/custom_nginx.template",
    })

    assert(helpers.start_kong {
      log_level             = "debug",
      prefix                = "servroot2",
      database              = strategy,
      proxy_listen          = "0.0.0.0:9000",
      proxy_listen_ssl      = "0.0.0.0:9443",
      admin_listen          = "0.0.0.0:9001",
      admin_gui_listen      = "0.0.0.0:9002",
      admin_ssl             = false,
      admin_gui_ssl         = false,
      db_update_frequency   = POLL_INTERVAL,
      plugins               = "proxy-cache",
    })

    client_1       = helpers.http_client("127.0.0.1", 8000)
    client_2       = helpers.http_client("127.0.0.1", 9000)
    admin_client_1 = helpers.http_client("127.0.0.1", 8001)
    admin_client_2 = helpers.http_client("127.0.0.1", 9001)
  end)

  teardown(function()
    helpers.stop_kong("servroot1")
    helpers.stop_kong("servroot2")
  end)

  before_each(function()
    client_1       = helpers.http_client("127.0.0.1", 8000)
    client_2       = helpers.http_client("127.0.0.1", 9000)
    admin_client_1 = helpers.http_client("127.0.0.1", 8001)
    admin_client_2 = helpers.http_client("127.0.0.1", 9001)
  end)

  after_each(function()
    client_1:close()
    client_2:close()
    admin_client_1:close()
    admin_client_2:close()
  end)

  describe("cache purge", function()
    local cache_key, cache_key2

    setup(function()
      -- prime cache entries on both instances
      local res_1 = get(client_1, "route-1.test")

      assert.res_status(200, res_1)
      assert.same("Miss", res_1.headers["X-Cache-Status"])
      cache_key = res_1.headers["X-Cache-Key"]

      local res_2 = get(client_2, "route-1.test")

      assert.res_status(200, res_2)
      assert.same("Miss", res_2.headers["X-Cache-Status"])
      assert.same(cache_key, res_2.headers["X-Cache-Key"])

      res_1 = get(client_1, "route-2.test")

      assert.res_status(200, res_1)
      assert.same("Miss", res_1.headers["X-Cache-Status"])
      cache_key2 = res_1.headers["X-Cache-Key"]
      assert.not_same(cache_key, cache_key2)

      local res_2 = get(client_2, "route-2.test")

      assert.res_status(200, res_2)
      assert.same("Miss", res_2.headers["X-Cache-Status"])
    end)

    it("propagates purges via cluster events mechanism", function()
      local res_1 = get(client_1, "route-1.test")

      assert.res_status(200, res_1)
      assert.same("Hit", res_1.headers["X-Cache-Status"])

      local res_2 = get(client_2, "route-1.test")

      assert.res_status(200, res_2)
      assert.same("Hit", res_2.headers["X-Cache-Status"])

      -- now purge the entry
      local res = assert(admin_client_1:delete("/proxy-cache/" .. plugin1.id .. "/caches/" .. cache_key))

      assert.res_status(204, res)

      helpers.wait_until(function()
        -- assert that the entity was purged from the second instance
        res = assert(admin_client_2:get("/proxy-cache/" .. plugin1.id .. "/caches/" .. cache_key, {
        }))
        res:read_body()
        return res.status == 404
      end, 10)

      -- refresh and purge with our second endpoint
      res_1 = get(client_1, "route-1.test")

      assert.res_status(200, res_1)
      assert.same("Miss", res_1.headers["X-Cache-Status"])

      res_2 = get(client_2, "route-1.test")

      assert.res_status(200, res_2)
      assert.same("Miss", res_2.headers["X-Cache-Status"])
      assert.same(cache_key, res_2.headers["X-Cache-Key"])

      -- now purge the entry
      res = assert(admin_client_1:delete("/proxy-cache/" .. cache_key))

      assert.res_status(204, res)

      admin_client_2:close()
      admin_client_2 = helpers.http_client("127.0.0.1", 9001)

      helpers.wait_until(function()
        -- assert that the entity was purged from the second instance
        res = assert(admin_client_2:get("/proxy-cache/" .. cache_key, {
        }))
        res:read_body()
        return res.status == 404
      end, 10)
    end)

    it("does not affect cache entries under other plugin instances", function()
      local res = assert(admin_client_1:get("/proxy-cache/" .. plugin2.id .. "/caches/" .. cache_key2, {
      }))

      assert.res_status(200, res)

      res = assert(admin_client_2:get("/proxy-cache/" .. plugin2.id .. "/caches/" .. cache_key2, {
      }))

      assert.res_status(200, res)
    end)

    it("propagates global purges", function()
      do
        local res = assert(admin_client_1:delete("/proxy-cache/"))

        assert.res_status(204, res)
      end

      helpers.wait_until(function()
        local res = assert(admin_client_1:get("/proxy-cache/" .. plugin2.id .. "/caches/" .. cache_key2, {
        }))
        res:read_body()
        return res.status == 404
      end, 10)

      helpers.wait_until(function()
        local res = assert(admin_client_2:get("/proxy-cache/" .. plugin2.id .. "/caches/" .. cache_key2, {
        }))
        res:read_body()
        return res.status == 404
      end, 10)
    end)
  end)
end)
end
