local helpers = require "spec.helpers"

describe("proxy-cache access", function()
  local client
  local cache_key

  setup(function()
    helpers.run_migrations()

    local api1 = assert(helpers.dao.apis:insert {
      name = "api-1",
      hosts = { "api-1.com" },
      upstream_url = "http://httpbin.org",
    })
    local api2 = assert(helpers.dao.apis:insert {
      name = "api-2",
      hosts = { "api-2.com" },
      upstream_url = "http://httpbin.org",
    })
    assert(helpers.dao.apis:insert {
      name = "api-3",
      hosts = { "api-3.com" },
      upstream_url = "http://httpbin.org",
    })
    assert(helpers.dao.apis:insert {
      name = "api-4",
      hosts = { "api-4.com" },
      upstream_url = "http://httpbin.org",
    })
    local api5 = assert(helpers.dao.apis:insert {
      name = "api-5",
      hosts = { "api-5.com" },
      upstream_url = "http://httpbin.org",
    })
    local api6 = assert(helpers.dao.apis:insert {
      name = "api-6",
      hosts = { "api-6.com" },
      upstream_url = "http://httpbin.org",
    })

    local consumer1 = assert(helpers.dao.consumers:insert {
      username = "bob",
    })
    assert(helpers.dao.keyauth_credentials:insert {
      key = "bob",
      consumer_id = consumer1.id,
    })
    local consumer2 = assert(helpers.dao.consumers:insert {
      username = "alice",
    })
    assert(helpers.dao.keyauth_credentials:insert {
      key = "alice",
      consumer_id = consumer2.id,
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api5.id,
      config = {},
    })

    assert(helpers.dao.plugins:insert {
      name = "proxy-cache",
      api_id = api1.id,
      config = {
        strategy = "memory",
        content_type = { "text/plain", "application/json" },
        memory = {
          dictionary_name = "kong",
        },
      },
    })

    assert(helpers.dao.plugins:insert {
      name = "proxy-cache",
      api_id = api2.id,
      config = {
        strategy = "memory",
        content_type = { "text/plain", "application/json" },
        memory = {
          dictionary_name = "kong",
        },
      },
    })

    -- global plugin for apis 3 and 4
    assert(helpers.dao.plugins:insert {
      name = "proxy-cache",
      config = {
        strategy = "memory",
        content_type = { "text/plain", "application/json" },
        memory = {
          dictionary_name = "kong",
        },
      },
    })

    assert(helpers.dao.plugins:insert {
      name = "proxy-cache",
      api_id = api5.id,
      config = {
        strategy = "memory",
        content_type = { "text/plain", "application/json" },
        memory = {
          dictionary_name = "kong",
        },
      },
    })

    assert(helpers.dao.plugins:insert {
      name = "proxy-cache",
      api_id = api6.id,
      config = {
        strategy = "memory",
        content_type = { "text/plain", "application/json" },
        memory = {
          dictionary_name = "kong",
        },
        cache_ttl = 2,
      },
    })

    assert(helpers.start_kong({
      custom_plugins = "proxy-cache",
    }))
    client = helpers.proxy_client()
  end)

  teardown(function()
    if client then
      client:close()
    end

    helpers.stop_kong()
  end)

  it("caches a simple request", function()
    local res = assert(client:send {
      method = "GET",
      path = "/get",
      headers = {
        host = "api-1.com",
      }
    })

    assert.res_status(200, res)
    assert.same("Miss", res.headers["X-Cache-Status"])

    -- cache key is an md5sum of the prefix uuid, method, and $request
    local cache_key1 = res.headers["X-Cache-Key"]
    assert.matches("^[%w%d]+$", cache_key1)
    assert.equals(32, #cache_key1)

    res = assert(client:send {
      method = "GET",
      path = "/get",
      headers = {
        host = "api-1.com",
      }
    })

    assert.res_status(200, res)

    assert.same("Hit", res.headers["X-Cache-Status"])
    local cache_key2 = res.headers["X-Cache-Key"]
    assert.same(cache_key1, cache_key2)

    -- examine this cache key against another plugin's cache key for the same req
    cache_key = cache_key1
  end)

  it("#o respects cache ttl", function()
    local res = assert(client:send {
      method = "GET",
      path = "/get",
      headers = {
        host = "api-6.com",
      }
    })

    assert.res_status(200, res)
    assert.same("Miss", res.headers["X-Cache-Status"])

    res = assert(client:send {
      method = "GET",
      path = "/get",
      headers = {
        host = "api-6.com",
      }
    })

    assert.res_status(200, res)

    assert.same("Hit", res.headers["X-Cache-Status"])

    -- give ourselves time to expire
    ngx.sleep(3)

    -- and go through the cycle again
    res = assert(client:send {
      method = "GET",
      path = "/get",
      headers = {
        host = "api-6.com",
      }
    })

    assert.res_status(200, res)
    assert.same("Miss", res.headers["X-Cache-Status"])

    res = assert(client:send {
      method = "GET",
      path = "/get",
      headers = {
        host = "api-6.com",
      }
    })

    assert.res_status(200, res)

    assert.same("Hit", res.headers["X-Cache-Status"])
  end)

  it("caches a streaming request", function()
    local res = assert(client:send {
      method = "GET",
      path = "/stream/5",
      headers = {
        host = "api-1.com",
      }
    })

    assert.res_status(200, res)
    assert.same("Miss", res.headers["X-Cache-Status"])

    res = assert(client:send {
      method = "GET",
      path = "/stream/5",
      headers = {
        host = "api-1.com",
      }
    })

    assert.res_status(200, res)

    assert.same("Hit", res.headers["X-Cache-Status"])
  end)

  it("uses an separate cache key betweens apis as a global plugin", function()
    local res = assert(client:send {
      method = "GET",
      path = "/get",
      headers = {
        host = "api-3.com",
      }
    })

    assert.res_status(200, res)
    assert.same("Miss", res.headers["X-Cache-Status"])

    local cache_key1 = res.headers["X-Cache-Key"]
    assert.matches("^[%w%d]+$", cache_key1)
    assert.equals(32, #cache_key1)

    res = assert(client:send {
      method = "GET",
      path = "/get",
      headers = {
        host = "api-4.com",
      }
    })

    assert.res_status(200, res)

    assert.same("Miss", res.headers["X-Cache-Status"])
    local cache_key2 = res.headers["X-Cache-Key"]
    assert.not_same(cache_key1, cache_key2)
  end)

  it("differentiates caches between instances", function()
    local res = assert(client:send {
      method = "GET",
      path = "/get",
      headers = {
        host = "api-2.com",
      }
    })

    assert.res_status(200, res)
    assert.same("Miss", res.headers["X-Cache-Status"])

    local cache_key1 = res.headers["X-Cache-Key"]
    assert.matches("^[%w%d]+$", cache_key1)
    assert.equals(32, #cache_key1)

    res = assert(client:send {
      method = "GET",
      path = "/get",
      headers = {
        host = "api-2.com",
      }
    })

    assert.res_status(200, res)

    assert.same("Hit", res.headers["X-Cache-Status"])
    local cache_key2 = res.headers["X-Cache-Key"]
    assert.same(cache_key1, cache_key2)

    assert.not_same(cache_key, cache_key1)
  end)

  it("uses request params as part of the cache key", function()
    local res = assert(client:send {
      method = "GET",
      path = "/get?a=b",
      headers = {
        host = "api-1.com",
      }
    })

    assert.res_status(200, res)
    assert.same("Miss", res.headers["X-Cache-Status"])

    res = assert(client:send {
      method = "GET",
      path = "/get?a=c",
      headers = {
        host = "api-1.com",
      }
    })

    assert.res_status(200, res)

    assert.same("Miss", res.headers["X-Cache-Status"])
  end)

  describe("handles authenticated apis", function()
    it("by ignoring cache if the request is unauthenticated", function()
      local res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "api-5.com",
        }
      })

      assert.res_status(401, res)
      assert.is_nil(res.headers["X-Cache-Status"])
    end)

    it("by maintaining a separate cache per consumer", function()
      local res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "api-5.com",
          apikey = "bob",
        }
      })

      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "api-5.com",
          apikey = "bob",
        }
      })

      assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])

      local res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "api-5.com",
          apikey = "alice",
        }
      })

      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "api-5.com",
          apikey = "alice",
        }
      })

      assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])

    end)
  end)

  describe("bypasses cache for uncacheable requests: ", function()
    it("request method", function()
      local res = assert(client:send {
        method = "POST",
        path = "/post",
        headers = {
          host = "api-1.com",
          ["Content-Type"] = "application/json",
        },
        {
          foo = "bar",
        },
      })

      assert.res_status(200, res)
      assert.same("Bypass", res.headers["X-Cache-Status"])
    end)
  end)

  describe("bypasses cache for uncacheable responses: ", function()
    it("response content type", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/418",
        headers = {
          host = "api-1.com",
        },
      })

      assert.res_status(418, res)
      assert.same("Bypass", res.headers["X-Cache-Status"])
    end)

    it("response content type", function()
      local res = assert(client:send {
        method = "GET",
        path = "/xml",
        headers = {
          host = "api-1.com",
        },
      })

      assert.res_status(200, res)
      assert.same("Bypass", res.headers["X-Cache-Status"])
    end)
  end)
end)
