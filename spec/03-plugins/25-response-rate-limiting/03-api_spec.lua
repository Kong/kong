local helpers = require "spec.helpers"
local Errors = require "kong.db.errors"
local cjson = require "cjson"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: response-rate-limiting (API) [#" .. strategy .. "]", function()
    local admin_client
    local bp

    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    describe("POST", function()

      before_each(function()
        admin_client = helpers.admin_client()
      end)

      after_each(function()
        if admin_client then
          admin_client:close()
        end
      end)

      it("errors on empty config", function()
        local route = bp.routes:insert {
          hosts = { "test1.test" },
        }
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name     = "response-ratelimiting",
            route = { id = route.id }
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({
          code = Errors.codes.SCHEMA_VIOLATION,
          name = "schema violation",
          fields = {
            config = {
              limits = "required field missing",
            }
          },
          message = "schema violation (config.limits: required field missing)",
        }, json)
      end)
      it("accepts proper config", function()
        local route = bp.routes:insert {
          hosts = { "test1.test" },
        }
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name     = "response-ratelimiting",
            route = { id = route.id },
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
