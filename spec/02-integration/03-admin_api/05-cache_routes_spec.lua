local helpers = require "spec.helpers"
local cache = require "kong.tools.database_cache"
local cjson = require "cjson"

describe("Admin API", function()
  local client, proxy_client
  setup(function()
    helpers.prepare_prefix()
    assert(helpers.start_kong())

    client = helpers.admin_client()
    proxy_client = helpers.proxy_client(2000)
  end)
  teardown(function()
    if client then
      client:close()
      proxy_client:close()
    end
    assert(helpers.stop_kong())
    helpers.clean_prefix()
  end)

  describe("/cache/{key}", function()
    setup(function()
      assert(helpers.dao.apis:insert {
        name = "api-cache",
        request_host = "cache.com",
        upstream_url = "http://mockbin.com"
      })
    end)

    describe("GET", function()
      it("returns 404 if not found", function()
        local res = assert(client:send {
          method = "GET",
          path = "/cache/_inexistent_"
        })
        assert.res_status(404, res)
      end)
      it("retrieves a cached entity", function()
        -- populate cache
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/",
          headers = {host = "cache.com"}
        })
        assert.res_status(200, res)

        res = assert(client:send {
          method = "GET",
          path = "/cache/"..cache.all_apis_by_dict_key()
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.by_dns)
      end)
    end)

    describe("DELETE", function()
      it("purges cached entity", function()
        -- populate cache
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/",
          headers = {host = "cache.com"}
        })
        assert.res_status(200, res)

        res = assert(client:send {
          method = "GET",
          path = "/cache/"..cache.all_apis_by_dict_key()
        })
        assert.res_status(200, res)

        -- delete cache
        res = assert(client:send {
          method = "DELETE",
          path = "/cache/"..cache.all_apis_by_dict_key()
        })
        assert.res_status(204, res)

        res = assert(client:send {
          method = "GET",
          path = "/cache/"..cache.all_apis_by_dict_key()
        })
        assert.res_status(404, res)
      end)
    end)

    describe("/cache/", function()
      describe("DELETE", function()
        it("purges all entities", function()
           -- populate cache
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/",
            headers = {host = "cache.com"}
          })
          assert.res_status(200, res)

          res = assert(client:send {
            method = "GET",
            path = "/cache/"..cache.all_apis_by_dict_key()
          })
          assert.res_status(200, res)

           -- delete cache
          res = assert(client:send {
            method = "DELETE",
            path = "/cache"
          })
          assert.res_status(204, res)

          res = assert(client:send {
            method = "GET",
            path = "/cache/"..cache.all_apis_by_dict_key()
          })
          assert.res_status(404, res)
        end)
      end)
    end)
  end)
end)
