local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Admin API /cache", function()
  local proxy_client
  local admin_client


  setup(function()
    helpers.get_db_utils()
    local api = assert(helpers.dao.apis:insert {
      name         = "api-cache",
      hosts        = { "cache.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(helpers.dao.plugins:insert {
      api_id = api.id,
      name   = "cache",
    })

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
    proxy_client = helpers.proxy_client()
    admin_client = helpers.admin_client()
  end)


  teardown(function()
    if admin_client then
      admin_client:close()
    end

    if proxy_client then
      proxy_client:close()
    end

    helpers.stop_kong()
  end)


  describe("/cache/:key", function()
    describe("GET", function()
      it("returns 404 if cache miss", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/cache/_inexistent_",
        })
        assert.res_status(404, res)
      end)

      it("returns 200 and value if cache hit", function()
        -- populate cache
        local res = assert(proxy_client:send {
          method = "POST",
          path = "/",
          body = {
            cache_key = "my_key",
            cache_value = "my_value",
          },
          headers = {
            ["Host"] = "cache.com",
            ["Content-Type"] = "application/x-www-form-urlencoded",
          },
        })
        assert.res_status(200, res)

        local admin_res = assert(admin_client:send {
          method = "GET",
          path = "/cache/my_key",
        })
        local body = assert.res_status(200, admin_res)
        local json = cjson.decode(body)

        assert.equal("my_value", json.message)
      end)
    end)


    describe("DELETE", function()
      it("purges a cached value", function()
        -- populate cache
        local res = assert(proxy_client:send {
          method = "POST",
          path = "/",
          body = {
            cache_key = "purge_me",
            cache_value = "value_to_purge",
          },
          headers = {
            ["Host"] = "cache.com",
            ["Content-Type"] = "application/x-www-form-urlencoded",
          },
        })
        assert.res_status(200, res)

        -- delete cache
        local admin_res = assert(admin_client:send {
          method = "DELETE",
          path = "/cache/purge_me",
        })
        assert.res_status(204, admin_res)

        admin_res = assert(admin_client:send {
          method = "GET",
          path = "/cache/purge_me",
        })
        assert.res_status(404, admin_res)
      end)
    end)
  end)


  describe("DELETE", function()
    it("purges all cached values", function()
      -- populate cache
      local res = assert(proxy_client:send {
        method = "POST",
        path = "/",
        body = {
          cache_key = "key_1",
          cache_value = "value_to_purge",
        },
        headers = {
          ["Host"] = "cache.com",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        },
      })
      assert.res_status(200, res)

      res = assert(proxy_client:send {
        method = "POST",
        path = "/",
        body = {
          cache_key = "key_2",
          cache_value = "value_to_purge",
        },
        headers = {
          ["Host"] = "cache.com",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        },
      })
      assert.res_status(200, res)

      local admin_res = assert(admin_client:send {
        method = "DELETE",
        path = "/cache",
      })
      assert.res_status(204, admin_res)

      admin_res = assert(admin_client:send {
        method = "GET",
        path = "/cache/key_1",
      })
      assert.res_status(404, admin_res)

      admin_res = assert(admin_client:send {
        method = "GET",
        path = "/cache/key_2",
      })
      assert.res_status(404, admin_res)
    end)
  end)
end)
