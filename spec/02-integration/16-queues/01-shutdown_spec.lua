local helpers    = require "spec.helpers"
local http_mock = require "spec.helpers.http_mock"

local HTTP_SERVER_PORT = helpers.get_available_port()


for _, strategy in helpers.each_strategy() do
  describe("queue graceful shutdown [#" .. strategy .. "]", function()
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })

      local service1 = bp.services:insert{
        protocol = "http",
        host     = helpers.mock_upstream_host,
        port     = helpers.mock_upstream_port,
      }

      local route1 = bp.routes:insert {
        hosts   = { "shutdown.flush.test" },
        service = service1
      }

      bp.plugins:insert {
        route = { id = route1.id },
        name     = "http-log",
        config   = {
          http_endpoint = "http://127.0.0.1:" .. HTTP_SERVER_PORT,
          queue = {
            max_batch_size = 1000,
            -- Using extra long max_coalescing_delay to ensure that we stop
            -- coalescing when a shutdown is initiated.
            max_coalescing_delay = 1000,
          },
        }
      }

      local service2 = bp.services:insert{
        protocol = "http",
        host     = helpers.mock_upstream_host,
        port     = helpers.mock_upstream_port,
      }

      local route2 = bp.routes:insert {
        hosts   = { "shutdown.dns.test" },
        service = service2
      }

      bp.plugins:insert {
        route = { id = route2.id },
        name     = "http-log",
        config   = {
          http_endpoint = "http://this-does-not-exist.example.test:80/this-does-not-exist",
          queue = {
            max_batch_size = 10,
            max_coalescing_delay = 10,
          },
        }
      }
    end)

    before_each(function()
      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
      helpers.stop_kong()
    end)

    it("queue is flushed before kong exits", function()
      local mock = http_mock.new(HTTP_SERVER_PORT)
      mock:start()
      finally(function()
        mock:stop()
      end)

      local res = assert(proxy_client:send({
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "shutdown.flush.test"
        }
      }))
      assert.res_status(200, res)

      -- We request a graceful shutdown, then start the HTTP server to consume the queued log entries
      local pid_file, err = helpers.stop_kong(nil, nil, nil, "QUIT", true)
      assert(pid_file, err)

      mock.eventually:has_request()

      helpers.wait_pid(pid_file)
      helpers.cleanup_kong()

    end)

    it("DNS queries can be performed when shutting down", function()

      local res = assert(proxy_client:send({
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "shutdown.dns.test"
        }
      }))
      assert.res_status(200, res)

      -- We request a graceful shutdown, which will flush the queue
      local res, err = helpers.stop_kong(nil, true, nil, "QUIT")
      assert(res, err)

      assert.logfile().has.line("DNS resolution failed: dns server error: 3 name error.")
    end)
  end)
end
