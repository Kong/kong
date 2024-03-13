local helpers  = require "spec.helpers"

local LMDB_MAP_SIZE = "10m"

for _, strategy in helpers.each_strategy() do
  if strategy ~= "off" then
    describe("Admin API #" .. strategy, function()
      local bp
      local client, route

      lazy_setup(function()
        bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
        })

        route = bp.routes:insert({
          paths = { "/route_with_max_safe_integer_priority"},
          regex_priority = 9007199254740992,
        })

        assert(helpers.start_kong({
          database = strategy,
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      before_each(function()
        client = assert(helpers.admin_client())
      end)

      after_each(function()
        if client then
          client:close()
        end
      end)

      it("the maximum safe integer can be accurately represented as a decimal number", function()
        local res = assert(client:send {
          method = "GET",
          path   = "/routes/" .. route.id
        })
        assert.res_status(200, res)
        assert.match_re(res:read_body(), "9007199254740992")
      end)
    end)
  end

  if strategy == "off" then
    describe("Admin API #off", function()
      local client

      lazy_setup(function()
        assert(helpers.start_kong({
          database = "off",
          lmdb_map_size = LMDB_MAP_SIZE,
          stream_listen = "127.0.0.1:9011",
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      before_each(function()
        client = assert(helpers.admin_client())
      end)

      after_each(function()
        if client then
          client:close()
        end
      end)

      it("the maximum safe integer can be accurately represented as a decimal number", function()
        local res = assert(client:send {
          method = "POST",
          path = "/config",
          body = {
            config = [[
            _format_version: "1.1"
            services:
            - name: my-service
              id: 0855b320-0dd2-547d-891d-601e9b38647f
              url: https://localhost
              routes:
              - name: my-route
                id: 481a9539-f49c-51b6-b2e2-fe99ee68866c
                paths:
                - /
                regex_priority: 9007199254740992
            ]],
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })

        assert.response(res).has.status(201)
        local res = client:get("/routes/481a9539-f49c-51b6-b2e2-fe99ee68866c")
        assert.res_status(200, res)
        assert.match_re(res:read_body(), "9007199254740992")
      end)
    end)
  end
end
