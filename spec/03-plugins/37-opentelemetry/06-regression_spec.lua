local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("opentelemetry regression #" .. strategy, function()
    local bp
    setup(function()
      bp = assert(helpers.get_db_utils(strategy, {
        "services",
        "routes",
        "plugins",
      }, { "opentelemetry" }))
    end)

    describe("#KAG-1061", function ()
      if strategy == "off" then
        return -- not relevant
      end

      local mock1, mock2
      local mock_port1, mock_port2
      setup(function()
        mock_port1 = helpers.get_available_port()
        mock_port2 = helpers.get_available_port()

        local http_srv = assert(bp.services:insert {
          name = "mock-service",
          host = helpers.mock_upstream_host,
          port = helpers.mock_upstream_port,
        })

        local route = assert(bp.routes:insert({ service = http_srv,
                                                protocols = { "http" },
                                                paths = { "/" }}))
        bp.plugins:insert({
          name = "opentelemetry",
          instance_name = "test1",
          route = route,
          service = http_srv,
          config = {
            traces_endpoint = "http://127.0.0.1:" .. mock_port1,
            batch_flush_delay = 0, -- report immediately
          }
        })

        assert(helpers.start_kong({
          database = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
          plugins = "opentelemetry",
          tracing_instrumentations = "all",
          tracing_sampling_rate = 1,
        }))
        -- we do not wait too long for the mock to receive the request
        mock1 = helpers.http_mock(mock_port1, {
          timeout = 5,
        })
        mock2 = helpers.http_mock(mock_port2, {
          timeout = 5,
        })
      end)

      teardown(function()
        helpers.stop_kong()
      end)

      it("test", function ()
        local client = assert(helpers.proxy_client())
        local res = assert(client:send {
          method = "GET",
          path = "/",
        })
        assert.res_status(200, res)

        -- sent to mock1
        assert(mock1())

        local admin_client = assert(helpers.admin_client())
        local res = assert(admin_client:send {
          method = "PATCH",
          path = "/plugins/test1",
          body = {
            config = {
              endpoint = "http://127.0.0.1:" .. mock_port2,
            }
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(200, res)

        -- keep sending requests until the reconfigure takes effect and
        -- the traces are sent to mock2
        local done
        local send_co = coroutine.create(function ()
          local time = 0
          while not done and time < 10 do
            local res = assert(client:send {
              method = "GET",
              path = "/",
            })
            assert.res_status(200, res)
            time = time + 1
          end
        end)

        coroutine.resume(send_co)

        assert(mock2())
        done = true
      end)
    end)
  end)
end
