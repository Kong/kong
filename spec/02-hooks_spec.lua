local helpers = require "spec.helpers"
local cjson = require "cjson"

for _ , strategy in helpers.each_strategy() do
  describe("Plugin: oauth2-introspection (hooks)" , function()
    local client , admin_client
    setup(function()
      local bp = helpers.get_db_utils(strategy, nil, {"introspection-endpoint",
                                                      "oauth2-introspection"})
      local introspection_url = string.format("http://%s/introspect" ,
        helpers.test_conf.proxy_listen[1])

      assert(bp.routes:insert {
        name = "introspection-api",
        paths = { "/introspect" },
      })

      local route1 = assert(bp.routes:insert {
        name = "route-1",
        hosts = { "introspection.com" },
      })
      assert(bp.plugins:insert {
        name = "oauth2-introspection",
        route = { id = route1.id },
        config = {
          introspection_url = introspection_url,
          authorization_value = "hello",
          ttl = 1
        }
      })

      assert(bp.consumers:insert {
        username = "bob"
      })

      assert(helpers.start_kong({
        database = strategy,
        plugins = "bundled,introspection-endpoint,oauth2-introspection",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        lua_package_path = "?/init.lua;./kong/?.lua;./spec/fixtures/?.lua;/kong-plugin/spec/fixtures/custom_plugins/?.lua;;"
      }))

      client = helpers.proxy_client()
      admin_client = helpers.admin_client()

      local res = assert(admin_client:send {
        method = "POST",
        path = "/routes/introspection-api/plugins/",
        body = {
          name = "introspection-endpoint"
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(201 , res)
    end)

    teardown(function()
      if admin_client then
        admin_client:close()
      end
      if client then
        client:close()
      end
      helpers.stop_kong()
    end)

    describe("Consumer" , function()
      it("invalidates a consumer by username" , function()
        local res = assert(client:send {
          method = "GET",
          path = "/request?access_token=valid_consumer",
          headers = {
            ["Host"] = "introspection.com"
          }
        })

        local body = cjson.decode(assert.res_status(200 , res))
        assert.equal("bob" , body.headers["x-consumer-username"])
        local consumer_id = body.headers["x-consumer-id"]
        assert.is_string(consumer_id)

        -- Deletes the consumer
        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/consumers/" .. consumer_id,
          headers = {
            ["Host"] = "introspection.com"
          }
        })
        assert.res_status(204 , res)

        -- ensure cache is invalidated
        helpers.wait_until(function()
          local res = assert(client:send {
            method = "GET",
            path = "/request?access_token=valid_consumer",
            headers = {
              ["Host"] = "introspection.com"
            }
          })
          local body = cjson.decode(assert.res_status(200 , res))
          return body.headers["x-consumer-username"] == nil
        end)
      end)
    end)
  end)
end
