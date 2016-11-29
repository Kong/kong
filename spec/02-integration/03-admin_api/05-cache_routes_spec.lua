local helpers = require "spec.helpers"
local cache = require "kong.tools.database_cache"
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

describe("Admin API", function()
  local client, proxy_client
  setup(function()
    assert(helpers.start_kong())
    client = helpers.admin_client()
    proxy_client = helpers.proxy_client(2000)
  end)
  teardown(function()
    if client then
      client:close()
      proxy_client:close()
    end
    helpers.stop_kong()
  end)

  describe("/cache/{key}", function()
    setup(function()
      assert(helpers.dao.apis:insert {
        name = "api-cache",
        hosts = { "cache.com" },
        upstream_url = "http://mockbin.com"
      })
    end)

    describe("GET", function()
      do_it("returns 404 if not found", function()
        local res = assert(client:send {
          method = "GET",
          path = "/cache/_inexistent_",
          query = { cache = current_cache },
        })
        assert.response(res).has.status(404)
      end)
      pending("retrieves a cached entity", function()
        -- populate cache
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/",
          headers = {host = "cache.com"},
          query = { cache = current_cache },
        })
        assert.response(res).has.status(200)

        res = assert(client:send {
          method = "GET",
          path = "/cache/"..cache.all_apis_by_dict_key(),
          query = { cache = current_cache },
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        if current_cache == "shm" then
          -- in this case the entry is jsonified (string type) and hence send as a "message" entry
          json = cjson.decode(json.message)
        end
        assert.is_table(json.by_dns)
      end)
    end)

    describe("DELETE", function()
      pending("purges cached entity", function()
        -- populate cache
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/",
          headers = {host = "cache.com"},
          query = { cache = current_cache },
        })
        assert.response(res).has.status(200)

        res = assert(client:send {
          method = "GET",
          path = "/cache/"..cache.all_apis_by_dict_key(),
          query = { cache = current_cache },
        })
        assert.response(res).has.status(200)

        -- delete cache
        res = assert(client:send {
          method = "DELETE",
          path = "/cache/"..cache.all_apis_by_dict_key(),
          query = { cache = current_cache },
        })
        assert.response(res).has.status(204)

        res = assert(client:send {
          method = "GET",
          path = "/cache/"..cache.all_apis_by_dict_key(),
          query = { cache = current_cache },
        })
        assert.response(res).has.status(404)
      end)
    end)

    describe("/cache/", function()
      describe("DELETE", function()
        pending("purges all entities", function()
           -- populate cache
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/",
            headers = {host = "cache.com"},
            query = { cache = current_cache },
          })
          assert.response(res).has.status(200)

          res = assert(client:send {
            method = "GET",
            path = "/cache/"..cache.all_apis_by_dict_key(),
            query = { cache = current_cache },
          })
          assert.response(res).has.status(200)

           -- delete cache
          res = assert(client:send {
            method = "DELETE",
            path = "/cache",
            query = { cache = current_cache },
          })
          assert.response(res).has.status(204)

          res = assert(client:send {
            method = "GET",
            path = "/cache/"..cache.all_apis_by_dict_key(),
            query = { cache = current_cache },
          })
          assert.response(res).has.status(404)
        end)
      end)
    end)
  end)
end)
