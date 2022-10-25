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
      local route, route2

      lazy_setup(function()
        local service = bp.services:insert()

        route = bp.routes:insert {
          hosts      = { "test1.com" },
          protocols  = { "http", "https" },
          service    = service
        }

        route2 = bp.routes:insert {
          hosts      = { "test2.com" },
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

      if strategy == "off" then
        it("sets policy to local by default on dbless", function()
          local id = "bac2038a-205c-4013-8830-e6dde503a3e3"
          local res = admin_client:post("/config", {
            body = {
              _format_version = "1.1",
              plugins = {
                {
                  id = id,
                  name = "rate-limiting",
                  config = {
                    second = 10
                  }
                }
              }
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(201, res))
          assert.equal("local", body.plugins[id].config.policy)
        end)

        it("does not allow setting policy to cluster on dbless", function()
          local id = "bac2038a-205c-4013-8830-e6dde503a3e3"
          local res = admin_client:post("/config", {
            body = {
              _format_version = "1.1",
              plugins = {
                {
                  id = id,
                  name = "rate-limiting",
                  config = {
                    policy = "cluster",
                    second = 10
                  }
                }
              }
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(400, res))
          assert.equal("expected one of: local, redis", body.fields.plugins[1].config.policy)
        end)

      else
        it("sets policy to local by default", function()
          local res = admin_client:post("/plugins", {
            body    = {
              name  = "rate-limiting",
              config = {
                second = 10
              }
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(201, res))
          assert.equal("local", body.config.policy)
        end)

        it("does allow setting policy to cluster on non-dbless", function()
          local res = admin_client:post("/plugins", {
            body    = {
              name  = "rate-limiting",
              route = { id = route2.id },
              config = {
                policy = 'cluster',
                second = 10
              }
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(201, res))
          assert.equal("cluster", body.config.policy)
        end)
      end
    end)
  end)
end
