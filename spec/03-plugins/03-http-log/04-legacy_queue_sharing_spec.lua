local cjson      = require "cjson"
local helpers    = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("legacy queue sharing [#" .. strategy .. "]", function()
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
        hosts   = { "sharing.test.route1" },
        service = service1
      }

      bp.plugins:insert {
        route = { id = route1.id },
        name     = "http-log",
        config   = {
          http_endpoint = "http://" .. helpers.mock_upstream_host
            .. ":"
            .. helpers.mock_upstream_port
            .. "/post_log/http",
          queue = {
            max_coalescing_delay = 1000,
            max_batch_size = 2,
          },
        }
      }

      local service2 = bp.services:insert{
        protocol = "http",
        host     = helpers.mock_upstream_host,
        port     = helpers.mock_upstream_port,
      }

      local route2 = bp.routes:insert {
        hosts   = { "sharing.test.route2" },
        service = service2
      }

      bp.plugins:insert {
        route = { id = route2.id },
        name     = "http-log",
        config   = {
          http_endpoint = "http://" .. helpers.mock_upstream_host
            .. ":"
            .. helpers.mock_upstream_port
            .. "/post_log/http",
          queue = {
            max_coalescing_delay = 1000,
            max_batch_size = 2,
          },
        }
      }


      local service3 = bp.services:insert{
        protocol = "http",
        host     = helpers.mock_upstream_host,
        port     = helpers.mock_upstream_port,
      }

      local route3 = bp.routes:insert {
        hosts   = { "sharing.test.route3" },
        service = service3
      }

      bp.plugins:insert {
        route = { id = route3.id },
        name     = "http-log",
        config   = {
          http_endpoint = "http://" .. helpers.mock_upstream_host
            .. ":"
            .. helpers.mock_upstream_port
            .. "/post_log/http_unshared",
          queue = {
            max_coalescing_delay = 0.01,
            max_batch_size = 2,
          },
        }
      }
    end)

    lazy_teardown(function()
      helpers.stop_kong()
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

    it("queues are shared based on upstream parameters", function()

      local res = assert(proxy_client:send({
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "sharing.test.route1"
        }
      }))
      assert.res_status(200, res)

      local res = assert(proxy_client:send({
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "sharing.test.route2"
        }
      }))
      assert.res_status(200, res)

      local res = assert(proxy_client:send({
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "sharing.test.route3"
        }
      }))
      assert.res_status(200, res)

      helpers.wait_until(function()
        local client = assert(helpers.http_client(helpers.mock_upstream_host,
          helpers.mock_upstream_port))
        local res = client:get("/read_log/http", {
          headers = {
            Accept = "application/json"
          }
        })
        local raw = assert.res_status(200, res)
        local body = cjson.decode(raw)
        if #body.entries == 2 then
          return true
        end
      end, 10)

      helpers.wait_until(function()
        local client = assert(helpers.http_client(helpers.mock_upstream_host,
          helpers.mock_upstream_port))
        local res = client:get("/read_log/http_unshared", {
          headers = {
            Accept = "application/json"
          }
        })
        local raw = assert.res_status(200, res)
        local body = cjson.decode(raw)
        if #body.entries == 1 then
          return true
        end
      end, 10)
    end)

  end)
end
