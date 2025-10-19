-- Test suite for Accept-Encoding cache key fix (Issue #12796)
-- This ensures compressed and uncompressed responses are cached separately

local helpers = require "spec.helpers"
local cjson = require "cjson"


for _, strategy in helpers.each_strategy() do
  describe("proxy-cache Accept-Encoding handling [#" .. strategy .. "]", function()
    local client
    local admin_client
    local bp

    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, nil, {"proxy-cache"})

      -- Route 1: Test basic gzip handling
      local route1 = assert(bp.routes:insert({
        hosts = { "accept-encoding-test.test" },
        paths = { "/test" },
      }))

      assert(bp.plugins:insert({
        name = "proxy-cache",
        route = { id = route1.id },
        config = {
          strategy = "memory",
          content_type = { "text/plain", "application/json" },
          memory = {
            dictionary_name = "kong",
          },
        },
      }))

      -- Route 2: Test with vary_headers
      local route2 = assert(bp.routes:insert({
        hosts = { "accept-encoding-vary.test" },
        paths = { "/test" },
      }))

      assert(bp.plugins:insert({
        name = "proxy-cache",
        route = { id = route2.id },
        config = {
          strategy = "memory",
          content_type = { "text/plain", "application/json" },
          vary_headers = { "X-Custom-Header" },
          memory = {
            dictionary_name = "kong",
          },
        },
      }))

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled,proxy-cache",
      }))

      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if admin_client then
        admin_client:close()
      end
      helpers.stop_kong()
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    describe("Test 1: Client WITH gzip support", function()
      it("should cache compressed response separately", function()
        -- First request with gzip support - should be a cache miss
        local res1 = assert(client:send({
          method = "GET",
          path = "/test",
          headers = {
            host = "accept-encoding-test.test",
            ["Accept-Encoding"] = "gzip",
          },
        }))

        local body1 = assert.res_status(200, res1)
        local cache_status1 = res1.headers["X-Cache-Status"]
        assert.equal("Miss", cache_status1)

        -- Second request with gzip support - should be a cache hit
        local res2 = assert(client:send({
          method = "GET",
          path = "/test",
          headers = {
            host = "accept-encoding-test.test",
            ["Accept-Encoding"] = "gzip",
          },
        }))

        local body2 = assert.res_status(200, res2)
        local cache_status2 = res2.headers["X-Cache-Status"]
        assert.equal("Hit", cache_status2)

        -- Verify cache keys are the same
        assert.equal(res1.headers["X-Cache-Key"], res2.headers["X-Cache-Key"])
      end)
    end)

    describe("Test 2: Client WITHOUT gzip support", function()
      it("should cache uncompressed response separately", function()
        -- Clear cache by making a unique request path
        local res1 = assert(client:send({
          method = "GET",
          path = "/test?nocache=1",
          headers = {
            host = "accept-encoding-test.test",
          },
        }))

        local body1 = assert.res_status(200, res1)
        local cache_status1 = res1.headers["X-Cache-Status"]
        assert.equal("Miss", cache_status1)

        -- Second request without gzip - should be a cache hit
        local res2 = assert(client:send({
          method = "GET",
          path = "/test?nocache=1",
          headers = {
            host = "accept-encoding-test.test",
          },
        }))

        local body2 = assert.res_status(200, res2)
        local cache_status2 = res2.headers["X-Cache-Status"]
        assert.equal("Hit", cache_status2)

        -- Verify cache keys are the same
        assert.equal(res1.headers["X-Cache-Key"], res2.headers["X-Cache-Key"])
      end)
    end)

    describe("Test 3: Both clients accessing same resource", function()
      it("should maintain separate cache entries for different Accept-Encoding", function()
        -- Client A: Request with gzip support
        local res_gzip1 = assert(client:send({
          method = "GET",
          path = "/test?both=1",
          headers = {
            host = "accept-encoding-test.test",
            ["Accept-Encoding"] = "gzip",
          },
        }))

        assert.res_status(200, res_gzip1)
        assert.equal("Miss", res_gzip1.headers["X-Cache-Status"])
        local cache_key_gzip = res_gzip1.headers["X-Cache-Key"]

        -- Client B: Request without gzip support
        local res_no_gzip1 = assert(client:send({
          method = "GET",
          path = "/test?both=1",
          headers = {
            host = "accept-encoding-test.test",
          },
        }))

        assert.res_status(200, res_no_gzip1)
        assert.equal("Miss", res_no_gzip1.headers["X-Cache-Status"])
        local cache_key_no_gzip = res_no_gzip1.headers["X-Cache-Key"]

        -- Verify different cache keys
        assert.not_equal(cache_key_gzip, cache_key_no_gzip)

        -- Client A: Second request with gzip - should hit its cache
        local res_gzip2 = assert(client:send({
          method = "GET",
          path = "/test?both=1",
          headers = {
            host = "accept-encoding-test.test",
            ["Accept-Encoding"] = "gzip",
          },
        }))

        assert.res_status(200, res_gzip2)
        assert.equal("Hit", res_gzip2.headers["X-Cache-Status"])
        assert.equal(cache_key_gzip, res_gzip2.headers["X-Cache-Key"])

        -- Client B: Second request without gzip - should hit its cache
        local res_no_gzip2 = assert(client:send({
          method = "GET",
          path = "/test?both=1",
          headers = {
            host = "accept-encoding-test.test",
          },
        }))

        assert.res_status(200, res_no_gzip2)
        assert.equal("Hit", res_no_gzip2.headers["X-Cache-Status"])
        assert.equal(cache_key_no_gzip, res_no_gzip2.headers["X-Cache-Key"])
      end)
    end)

    describe("Test 4: Edge cases", function()
      it("should handle multiple encodings", function()
        local res1 = assert(client:send({
          method = "GET",
          path = "/test?multi=1",
          headers = {
            host = "accept-encoding-test.test",
            ["Accept-Encoding"] = "gzip, deflate, br",
          },
        }))

        assert.res_status(200, res1)
        assert.equal("Miss", res1.headers["X-Cache-Status"])
        local cache_key1 = res1.headers["X-Cache-Key"]

        -- Same encodings, different order - should use same cache key
        local res2 = assert(client:send({
          method = "GET",
          path = "/test?multi=1",
          headers = {
            host = "accept-encoding-test.test",
            ["Accept-Encoding"] = "br, deflate, gzip",
          },
        }))

        assert.res_status(200, res2)
        -- Should hit cache because encodings are normalized
        assert.equal("Hit", res2.headers["X-Cache-Status"])
        assert.equal(cache_key1, res2.headers["X-Cache-Key"])
      end)

      it("should handle case variations", function()
        local res1 = assert(client:send({
          method = "GET",
          path = "/test?case=1",
          headers = {
            host = "accept-encoding-test.test",
            ["Accept-Encoding"] = "GZIP",
          },
        }))

        assert.res_status(200, res1)
        assert.equal("Miss", res1.headers["X-Cache-Status"])
        local cache_key1 = res1.headers["X-Cache-Key"]

        -- Lowercase variant should hit same cache
        local res2 = assert(client:send({
          method = "GET",
          path = "/test?case=1",
          headers = {
            host = "accept-encoding-test.test",
            ["Accept-Encoding"] = "gzip",
          },
        }))

        assert.res_status(200, res2)
        assert.equal("Hit", res2.headers["X-Cache-Status"])
        assert.equal(cache_key1, res2.headers["X-Cache-Key"])

        -- Mixed case should also hit same cache
        local res3 = assert(client:send({
          method = "GET",
          path = "/test?case=1",
          headers = {
            host = "accept-encoding-test.test",
            ["Accept-Encoding"] = "Gzip",
          },
        }))

        assert.res_status(200, res3)
        assert.equal("Hit", res3.headers["X-Cache-Status"])
        assert.equal(cache_key1, res3.headers["X-Cache-Key"])
      end)

      it("should handle quality values", function()
        local res1 = assert(client:send({
          method = "GET",
          path = "/test?quality=1",
          headers = {
            host = "accept-encoding-test.test",
            ["Accept-Encoding"] = "gzip;q=1.0, deflate;q=0.8",
          },
        }))

        assert.res_status(200, res1)
        assert.equal("Miss", res1.headers["X-Cache-Status"])
        local cache_key1 = res1.headers["X-Cache-Key"]

        -- Different quality values but same encodings should hit cache
        local res2 = assert(client:send({
          method = "GET",
          path = "/test?quality=1",
          headers = {
            host = "accept-encoding-test.test",
            ["Accept-Encoding"] = "gzip;q=0.9, deflate;q=1.0",
          },
        }))

        assert.res_status(200, res2)
        assert.equal("Hit", res2.headers["X-Cache-Status"])
        assert.equal(cache_key1, res2.headers["X-Cache-Key"])
      end)

      it("should treat empty and missing Accept-Encoding as same", function()
        local res1 = assert(client:send({
          method = "GET",
          path = "/test?empty=1",
          headers = {
            host = "accept-encoding-test.test",
          },
        }))

        assert.res_status(200, res1)
        assert.equal("Miss", res1.headers["X-Cache-Status"])
        local cache_key1 = res1.headers["X-Cache-Key"]

        -- Empty header should hit same cache
        local res2 = assert(client:send({
          method = "GET",
          path = "/test?empty=1",
          headers = {
            host = "accept-encoding-test.test",
            ["Accept-Encoding"] = "",
          },
        }))

        assert.res_status(200, res2)
        assert.equal("Hit", res2.headers["X-Cache-Status"])
        assert.equal(cache_key1, res2.headers["X-Cache-Key"])
      end)
    end)

    describe("Test 5: Works with vary_headers configuration", function()
      it("should include both Accept-Encoding and vary_headers in cache key", function()
        -- Request with gzip and custom header
        local res1 = assert(client:send({
          method = "GET",
          path = "/test?vary=1",
          headers = {
            host = "accept-encoding-vary.test",
            ["Accept-Encoding"] = "gzip",
            ["X-Custom-Header"] = "value1",
          },
        }))

        assert.res_status(200, res1)
        assert.equal("Miss", res1.headers["X-Cache-Status"])
        local cache_key1 = res1.headers["X-Cache-Key"]

        -- Same Accept-Encoding, different custom header - should miss
        local res2 = assert(client:send({
          method = "GET",
          path = "/test?vary=1",
          headers = {
            host = "accept-encoding-vary.test",
            ["Accept-Encoding"] = "gzip",
            ["X-Custom-Header"] = "value2",
          },
        }))

        assert.res_status(200, res2)
        assert.equal("Miss", res2.headers["X-Cache-Status"])
        local cache_key2 = res2.headers["X-Cache-Key"]
        assert.not_equal(cache_key1, cache_key2)

        -- Different Accept-Encoding, same custom header - should miss
        local res3 = assert(client:send({
          method = "GET",
          path = "/test?vary=1",
          headers = {
            host = "accept-encoding-vary.test",
            ["X-Custom-Header"] = "value1",
          },
        }))

        assert.res_status(200, res3)
        assert.equal("Miss", res3.headers["X-Cache-Status"])
        local cache_key3 = res3.headers["X-Cache-Key"]
        assert.not_equal(cache_key1, cache_key3)
        assert.not_equal(cache_key2, cache_key3)

        -- Same Accept-Encoding and custom header - should hit
        local res4 = assert(client:send({
          method = "GET",
          path = "/test?vary=1",
          headers = {
            host = "accept-encoding-vary.test",
            ["Accept-Encoding"] = "gzip",
            ["X-Custom-Header"] = "value1",
          },
        }))

        assert.res_status(200, res4)
        assert.equal("Hit", res4.headers["X-Cache-Status"])
        assert.equal(cache_key1, res4.headers["X-Cache-Key"])
      end)
    end)
  end)
end
