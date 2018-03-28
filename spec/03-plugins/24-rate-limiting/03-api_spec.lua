

local cjson   = require "cjson"
local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: rate-limiting (API) [#" .. strategy .. "]", function()
    local admin_client
    local bp

    setup(function()
      bp = helpers.get_db_utils(strategy)
    end)

    teardown(function()
      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong()
    end)

    describe("POST", function()
      local route

      setup(function()
        local service = bp.services:insert()

        route = bp.routes:insert {
          hosts      = { "test1.com" },
          protocols  = { "http", "https" },
          service    = service
        }

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))

        admin_client = helpers.admin_client()
      end)

      it("should not save with empty config", function()
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name             = "rate-limiting",
            route_id         = route.id,
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ config = "You need to set at least one limit: second, minute, hour, day, month, year" }, json)
      end)

      it("should save with proper config", function()
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name             = "rate-limiting",
            route_id         = route.id,
            config           = {
              second = 10
            }
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(201, res))
        assert.equal(10, body.config.second)
      end)
    end)
  end)
end
