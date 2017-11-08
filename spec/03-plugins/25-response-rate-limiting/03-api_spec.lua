local helpers = require "spec.helpers"
local cjson   = require "cjson"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: response-rate-limiting (API) [#" .. strategy .. "]", function()
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
        route = bp.routes:insert {
          hosts = { "test1.com" },
        }

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))

        admin_client = helpers.admin_client()
      end)

      it("errors on empty config", function()
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name     = "response-ratelimiting",
            route_id = route.id
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ config = "You need to set at least one limit name" }, json)
      end)
      it("accepts proper config", function()
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name     = "response-ratelimiting",
            route_id = route.id,
            config   = {
              limits = {
                video = { second = 10 }
              }
            }
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(201, res))
        assert.equal(10, body.config.limits.video.second)
      end)
    end)
  end)
end
