local helpers      = require "spec.helpers"


local POLL_INTERVAL = 0.3


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

  local wait_for_propagation

  setup(function()
    bp = helpers.get_db_utils(strategy, nil, {"proxy-cache"})

    route1 = assert(bp.routes:insert {
      hosts = { "route-1.com" },
    })

    route2 = assert(bp.routes:insert {
      hosts = { "route-2.com" },
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

    local db_update_propagation = strategy == "cassandra" and 3 or 0

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
      db_update_propagation = db_update_propagation,
      plugins        = "proxy-cache",
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
      db_update_propagation = db_update_propagation,
      plugins        = "proxy-cache",
    })

    client_1       = helpers.http_client("127.0.0.1", 8000)
    client_2       = helpers.http_client("127.0.0.1", 9000)
    admin_client_1 = helpers.http_client("127.0.0.1", 8001)
    admin_client_2 = helpers.http_client("127.0.0.1", 9001)

    wait_for_propagation = function()
      ngx.sleep(POLL_INTERVAL + db_update_propagation)
    end
  end)

  teardown(function()
    helpers.stop_kong("servroot1", true)
    helpers.stop_kong("servroot2", true)
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
      local res_1 = assert(client_1:send {
        method = "GET",
        path = "/get",
        headers = {
          Host = "route-1.com",
        },
      })

      assert.res_status(200, res_1)
      assert.same("Miss", res_1.headers["X-Cache-Status"])
      cache_key = res_1.headers["X-Cache-Key"]

      local res_2 = assert(client_2:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-1.com",
        },
      })

      assert.res_status(200, res_2)
      assert.same("Miss", res_2.headers["X-Cache-Status"])
      assert.same(cache_key, res_2.headers["X-Cache-Key"])

      res_1 = assert(client_1:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-2.com",
        },
      })

      assert.res_status(200, res_1)
      assert.same("Miss", res_1.headers["X-Cache-Status"])
      cache_key2 = res_1.headers["X-Cache-Key"]
      assert.not_same(cache_key, cache_key2)

      res_2 = assert(client_2:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-2.com",
        },
      })

      assert.res_status(200, res_2)
      assert.same("Miss", res_2.headers["X-Cache-Status"])
    end)

    it("propagates purges via cluster events mechanism", function()
      local res_1 = assert(client_1:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-1.com",
        },
      })

      assert.res_status(200, res_1)
      assert.same("Hit", res_1.headers["X-Cache-Status"])

      local res_2 = assert(client_2:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-1.com",
        },
      })

      assert.res_status(200, res_2)
      assert.same("Hit", res_2.headers["X-Cache-Status"])

      -- now purge the entry
      local res = assert(admin_client_1:send {
        method = "DELETE",
        path = "/proxy-cache/" .. plugin1.id .. "/caches/" .. cache_key,
      })

      assert.res_status(204, res)

      -- wait for propagation
      wait_for_propagation()

      -- assert that the entity was purged from the second instance
      res = assert(admin_client_2:send {
        method = "GET",
        path = "/proxy-cache/" .. plugin1.id .. "/caches/" .. cache_key,
      })

      assert.res_status(404, res)

      -- refresh and purge with our second endpoint
      res_1 = assert(client_1:send {
        method = "GET",
        path = "/get",
        headers = {
          Host = "route-1.com",
        },
      })

      assert.res_status(200, res_1)
      assert.same("Miss", res_1.headers["X-Cache-Status"])

      res_2 = assert(client_2:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-1.com",
        },
      })

      assert.res_status(200, res_2)
      assert.same("Miss", res_2.headers["X-Cache-Status"])
      assert.same(cache_key, res_2.headers["X-Cache-Key"])

      -- now purge the entry
      res = assert(admin_client_1:send {
        method = "DELETE",
        path = "/proxy-cache/" .. cache_key,
      })

      assert.res_status(204, res)

      -- wait for propagation
      wait_for_propagation()

      -- assert that the entity was purged from the second instance
      res = assert(admin_client_2:send {
        method = "GET",
        path = "/proxy-cache/" .. cache_key,
      })

      assert.res_status(404, res)

    end)

    it("does not affect cache entries under other plugin instances", function()
      local res = assert(admin_client_1:send {
        method = "GET",
        path = "/proxy-cache/" .. plugin2.id .. "/caches/" .. cache_key2,
      })

      assert.res_status(200, res)

      local res = assert(admin_client_2:send {
        method = "GET",
        path = "/proxy-cache/" .. plugin2.id .. "/caches/" .. cache_key2,
      })

      assert.res_status(200, res)
    end)

    it("propagates global purges", function()
      local res = assert(admin_client_1:send {
        method = "DELETE",
        path = "/proxy-cache/",
      })

      assert.res_status(204, res)

      wait_for_propagation()

      local res = assert(admin_client_1:send {
        method = "GET",
        path = "/proxy-cache/" .. plugin2.id .. "/caches/" .. cache_key2,
      })

      assert.res_status(404, res)

      local res = assert(admin_client_2:send {
        method = "GET",
        path = "/proxy-cache/" .. plugin2.id .. "/caches/" .. cache_key2,
      })

      assert.res_status(404, res)
    end)
  end)
end)
end
