local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("Observability Logs", function ()
    describe("ngx.log patch", function()
      local proxy_client
      local post_function_access = [[
        local threads = {}
        local n_threads = 100

        for i = 1, n_threads do
          threads[i] = ngx.thread.spawn(function()
            ngx.log(ngx.INFO, "thread_" .. i .. " logged")
          end)
        end

        for i = 1, n_threads do
          ngx.thread.wait(threads[i])
        end
      ]]

      lazy_setup(function()
        local bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "plugins",
        })

        local http_srv = assert(bp.services:insert {
          name = "mock-service",
          host = helpers.mock_upstream_host,
          port = helpers.mock_upstream_port,
        })

        local logs_route = assert(bp.routes:insert({ service = http_srv,
                                                     protocols = { "http" },
                                                     paths = { "/logs" }}))

        assert(bp.plugins:insert({
          name = "post-function",
          route = logs_route,
          config = {
            access = { post_function_access },
          },
        }))

        -- only needed to enable the log collection hook
        assert(bp.plugins:insert({
          name = "opentelemetry",
          route = logs_route,
          config = {
            logs_endpoint = "http://" .. helpers.mock_upstream_host .. ":" .. helpers.mock_upstream_port,
          }
        }))

        helpers.start_kong({
          database = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
          plugins = "opentelemetry,post-function",
        })
        proxy_client = helpers.proxy_client()
      end)

      lazy_teardown(function()
        if proxy_client then
          proxy_client:close()
        end
        helpers.stop_kong()
      end)

      it("does not produce yielding and concurrent executions", function ()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/logs",
        })
        assert.res_status(200, res)

        -- plugin produced logs:
        assert.logfile().has.line("thread_1 logged", true, 10)
        assert.logfile().has.line("thread_100 logged", true, 10)
        -- plugin did not produce concurrent accesses to ngx.log:
        assert.logfile().has.no.line("[error]", true)
      end)
    end)
  end)
end
