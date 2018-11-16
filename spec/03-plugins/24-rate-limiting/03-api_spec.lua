

local cjson   = require "cjson"
local helpers = require "spec.helpers"
local Errors  = require "kong.db.errors"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: rate-limiting (API) [#" .. strategy .. "]", function()
    local admin_client
    local bp

    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })
    end)

    lazy_teardown(function()
      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong(nil, true)
    end)

    describe("POST", function()
      local route

      lazy_setup(function()
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
            name  = "rate-limiting",
            route = { id = route.id },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        local msg = [[at least one of these fields must be non-empty: ]] ..
                    [['config.second', 'config.minute', 'config.hour', ]] ..
                    [['config.day', 'config.month', 'config.year']]
        assert.same({
          code = Errors.codes.SCHEMA_VIOLATION,
          fields = {
            ["@entity"] = { msg }
          },
          message = "schema violation (" .. msg .. ")",
          name = "schema violation",
        }, json)
      end)

      it("should save with proper config", function()
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name             = "rate-limiting",
            route = { id = route.id },
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
