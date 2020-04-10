local helpers = require "spec.helpers"
local cjson = require "cjson"

local PLUGIN_NAME = "upstream-timeout"

for _, strategy in helpers.each_strategy() do
  describe("Plugin API config validator:", function ()
    local proxy_client
    local route1

    setup(function ()
      local bp = helpers.get_db_utils(strategy)

      route1 = bp.routes:insert {
        hosts = { "schema_plugin_test.com" }
      }

      assert(helpers.start_kong {
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template"
      })
      proxy_client = helpers.admin_client()
    end)

    teardown(function ()
      if proxy_client then
        proxy_client:close()
      end
      helpers.stop_kong()
    end)

    it("fails when timeout conf is not a positive integer", function ()
      local res = assert(proxy_client:send {
        method = "POST",
        path = "/plugins/",
        body = {
          name = PLUGIN_NAME,
          config = {
            read_timeout = "invalid_type_string"
          },
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      local body = assert.response(res).has.status(400)
      local json = cjson.decode(body)
      assert.same("schema violation", json.name)

      res = assert(proxy_client:send {
        method = "POST",
        path = "/plugins",
        body = {
          name = PLUGIN_NAME,
          config = {
            read_timeout = -234324
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.response(res).has.status(400)
    end)


    local function make_request(client, conf, route)
      return (client:send {
        method = "POST",
        path = "/plugins/",
        body = {
          name = PLUGIN_NAME,
          config = conf,
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
    end

    it("succeeds if positive integer", function ()
      local res = assert(make_request(proxy_client, { read_timeout = 500 }, route1))
      assert.response(res).has.status(201)
    end)

  end)
end 
