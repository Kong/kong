local handler   = require "kong.plugins.request-size-limiting.handler"
local helpers   = require "spec.helpers"
local cjson     = require "cjson"


local size_units                 = handler.size_units
local unit_multiplication_factor = handler.unit_multiplication_factor


local TEST_SIZE = 2
local MB        = 2^20


for _, strategy in helpers.each_strategy() do
  describe("Plugin: request-size-limiting (access) [#" .. strategy .. "]", function()
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })

      local route = bp.routes:insert {
        hosts = { "limit.com" },
      }

      bp.plugins:insert {
        name     = "request-size-limiting",
        route = { id = route.id },
        config   = {
          allowed_payload_size = TEST_SIZE,
        }
      }

      local route2 = bp.routes:insert {
        hosts = { "required.com" },
      }

      bp.plugins:insert {
        name     = "request-size-limiting",
        route = { id = route2.id },
        config   = {
          allowed_payload_size = TEST_SIZE,
          require_content_length = true,
        }
      }

      for _, unit in ipairs(size_units) do
        local route = bp.routes:insert {
          hosts = { string.format("limit_%s.com", unit) },
        }

        bp.plugins:insert {
          name     = "request-size-limiting",
          route = { id = route.id },
          config   = {
            allowed_payload_size = TEST_SIZE,
            size_unit = unit
          }
        }
      end

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      helpers.stop_kong()
    end)

    describe("with Content-Length", function()
      it("works if size is lower than limit", function()
        local body = string.rep("a", (TEST_SIZE * MB))
        local res = assert(proxy_client:request {
          method  = "POST",
          path    = "/request",
          body    = body,
          headers = {
            ["Host"]           = "limit.com",
            ["Content-Length"] = #body
          }
        })
        assert.res_status(200, res)
      end)

      it("works if size is lower than limit and Expect header", function()
        local body = string.rep("a", (TEST_SIZE * MB))
        local res = assert(proxy_client:request {
          method  = "POST",
          path    = "/request",
          body    = body,
          headers = {
            ["Host"]           = "limit.com",
            ["Expect"]         = "100-continue",
            ["Content-Length"] = #body
          }
        })
        assert.res_status(200, res)
      end)

      it("blocks if size is greater than limit", function()
        local body = string.rep("a", (TEST_SIZE * MB) + 1)
        local res = assert(proxy_client:request {
          method  = "POST",
          path    = "/request",
          body    = body,
          headers = {
            ["Host"]           = "limit.com",
            ["Content-Length"] = #body
          }
        })
        local body = assert.res_status(413, res)
        local json = cjson.decode(body)
        assert.same({ message = "Request size limit exceeded" }, json)
      end)

      it("blocks if size is greater than limit and Expect header", function()
        local body = string.rep("a", (TEST_SIZE * MB) + 1)
        local res = assert(proxy_client:request {
          method  = "POST",
          path    = "/request",
          body    = body,
          headers = {
            ["Host"]           = "limit.com",
            ["Expect"]         = "100-continue",
            ["Content-Length"] = #body
          }
        })
        local body = assert.res_status(417, res)
        local json = cjson.decode(body)
        assert.same({ message = "Request size limit exceeded" }, json)
      end)

      for _, unit in ipairs(size_units) do
        it("blocks if size is greater than limit when unit in " .. unit, function()
          local body = string.rep("a", (TEST_SIZE * unit_multiplication_factor[unit]) + 1)
          local res = assert(proxy_client:request {
            method  = "POST",
            path    = "/request",
            body    = body,
            headers = {
              ["Host"]           = string.format("limit_%s.com", unit),
              ["Content-Length"] = #body
            }
          })
          local body = assert.res_status(413, res)
          local json = cjson.decode(body)
          assert.same({ message = "Request size limit exceeded" }, json)
        end)
      end

      for _, unit in ipairs(size_units) do
        it("works if size is less than limit when unit in " .. unit, function()
          local body = string.rep("a", (TEST_SIZE * unit_multiplication_factor[unit]) - 1)
          local res = assert(proxy_client:request {
            method  = "POST",
            path    = "/request",
            body    = body,
            headers = {
              ["Host"]           = string.format("limit_%s.com", unit),
              ["Content-Length"] = #body
            }
          })
          assert.res_status(200, res)
        end)
      end
    end)

    describe("without Content-Length", function()
      it("works if size is lower than limit", function()
        local body = string.rep("a", (TEST_SIZE * MB))
        local res = assert(proxy_client:request {
          dont_add_content_length = true,
          method  = "GET", -- if POST, then lua-rsty-http adds content-length anyway
          path    = "/request",
          body    = body,
          headers = {
            ["Host"] = "limit.com"
          }
        })
        assert.res_status(200, res)
      end)

      it("works if size is lower than limit and Expect header", function()
        local body = string.rep("a", (TEST_SIZE * MB))
        local res = assert(proxy_client:request {
          dont_add_content_length = true,
          method  = "GET", -- if POST, then lua-rsty-http adds content-length anyway
          path    = "/request",
          body    = body,
          headers = {
            ["Host"]   = "limit.com",
            ["Expect"] = "100-continue"
          }
        })
        assert.res_status(200, res)
      end)

      it("blocks if size is greater than limit", function()
        local body = string.rep("a", (TEST_SIZE * MB) + 1)
        local res = assert(proxy_client:request {
          dont_add_content_length = true,
          method  = "GET", -- if POST, then lua-rsty-http adds content-length anyway
          path    = "/request",
          body    = body,
          headers = {
            ["Host"] = "limit.com"
          }
        })
        local body = assert.res_status(413, res)
        local json = cjson.decode(body)
        assert.same({ message = "Request size limit exceeded" }, json)
      end)

      it("blocks if size is greater than limit and Expect header", function()
        local body = string.rep("a", (TEST_SIZE * MB) + 1)
        local res = assert(proxy_client:request {
          dont_add_content_length = true,
          method  = "GET", -- if POST, then lua-rsty-http adds content-length anyway
          path    = "/request",
          body    = body,
          headers = {
            ["Host"]   = "limit.com",
            ["Expect"] = "100-continue"
          }
        })
        local body = assert.res_status(417, res)
        local json = cjson.decode(body)
        assert.same({ message = "Request size limit exceeded" }, json)
      end)

      for _, unit in ipairs(size_units) do
        it("blocks if size is greater than limit when unit in " .. unit, function()
          local body = string.rep("a", (TEST_SIZE * unit_multiplication_factor[unit]) + 1)
          local res = assert(proxy_client:request {
            dont_add_content_length = true,
            method  = "GET", -- if POST, then lua-rsty-http adds content-length anyway
            path    = "/request",
            body    = body,
            headers = {
              ["Host"]           = string.format("limit_%s.com", unit),
            }
          })
          local body = assert.res_status(413, res)
          local json = cjson.decode(body)
          assert.same({ message = "Request size limit exceeded" }, json)
        end)
      end

      for _, unit in ipairs(size_units) do
        it("works if size is less than limit when unit in " .. unit, function()
          local body = string.rep("a", (TEST_SIZE * unit_multiplication_factor[unit]))
          local res = assert(proxy_client:request {
            dont_add_content_length = true,
            method  = "GET", -- if POST, then lua-rsty-http adds content-length anyway
            path    = "/request",
            body    = body,
            headers = {
              ["Host"]           = string.format("limit_%s.com", unit),
            }
          })
          assert.res_status(200, res)
        end)
      end
    end)

    describe("Content-Length header required", function()
      it("blocks if header is not provided", function()
        local res = assert(proxy_client:request {
          dont_add_content_length = true,
          method  = "GET", -- if POST, then lua-rsty-http adds content-length anyway
          path    = "/request",
          headers = {
            ["Host"] = "required.com",
          }
        })
        assert.response(res).has.status(411)
      end)
    end)
  end)
end
