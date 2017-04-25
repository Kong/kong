local helpers = require "spec.helpers"
local cjson = require "cjson"

local current_cache
local caches = { "lua", "shm" }
local function do_it(desc, func)
  for _, cache in ipairs(caches) do
    it("[cache="..cache.."] "..desc,
      function(...)
        current_cache = cache
        return func(...)
      end)
  end
end

describe("Admin API /cache/{key}", function()
  local api_client, proxy_client
  setup(function()
    local api = assert(helpers.dao.apis:insert {
      name = "api-cache",
      hosts = { "cache.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      api_id = api.id,
      name = "first-request",
    })

    assert(helpers.start_kong({
      custom_plugins = "first-request",
    }))
    api_client = helpers.admin_client()
    proxy_client = helpers.proxy_client(2000)
  end)
  teardown(function()
    if api_client then
      api_client:close()
      proxy_client:close()
    end
    helpers.stop_kong()
  end)

  describe("GET", function()
    do_it("returns 404 if not found", function()
      local res = assert(api_client:send {
        method = "GET",
        path = "/cache/_inexistent_",
        query = { cache = current_cache },
      })
      assert.response(res).has.status(404)
    end)
    it("retrieves a cached entity", function()
      -- populate cache
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/",
        headers = {host = "cache.com"},
        query = { cache = current_cache },
      })
      assert.response(res).has.status(200)

      res = assert(api_client:send {
        method = "GET",
        path = "/cache/requested",
        query = { cache = current_cache },
      })
      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      if current_cache == "shm" then
        -- in this case the entry is jsonified (string type) and hence send as a "message" entry
        json = cjson.decode(json.message)
      end
      assert.True(json.requested)
    end)
  end)

  describe("DELETE", function()
    it("purges cached entity", function()
      -- populate cache
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/",
        headers = {host = "cache.com"},
        query = { cache = current_cache },
      })
      assert.response(res).has.status(200)

      res = assert(api_client:send {
        method = "GET",
        path = "/cache/requested",
        query = { cache = current_cache },
      })
      assert.response(res).has.status(200)

      -- delete cache
      res = assert(api_client:send {
        method = "DELETE",
        path = "/cache/requested",
        query = { cache = current_cache },
      })
      assert.response(res).has.status(204)

      res = assert(api_client:send {
        method = "GET",
        path = "/cache/requested",
        query = { cache = current_cache },
      })
      assert.response(res).has.status(404)
    end)
  end)

  describe("/cache/", function()
    describe("DELETE", function()
      it("purges all entities", function()
         -- populate cache
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/",
          headers = {host = "cache.com"},
          query = { cache = current_cache },
        })
        assert.response(res).has.status(200)

        res = assert(api_client:send {
          method = "GET",
          path = "/cache/requested",
          query = { cache = current_cache },
        })
        assert.response(res).has.status(200)

         -- delete cache
        res = assert(api_client:send {
          method = "DELETE",
          path = "/cache",
          query = { cache = current_cache },
        })
        assert.response(res).has.status(204)

        res = assert(api_client:send {
          method = "GET",
          path = "/cache/requested",
          query = { cache = current_cache },
        })
        assert.response(res).has.status(404)
      end)
    end)
  end)
end)
