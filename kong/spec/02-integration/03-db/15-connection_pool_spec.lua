local helpers = require "spec.helpers"
local cjson = require "cjson"

for pool_size, backlog_size in ipairs({ 2, 3 }) do
  describe("#postgres Postgres connection pool with pool=" .. pool_size .. "and backlog=" .. backlog_size, function()
    local client
    lazy_setup(function()
      local bp = helpers.get_db_utils("postgres", {
        "plugins",
      }, {
        "slow-query"
      })

      bp.plugins:insert({
        name = "slow-query",
      })

      assert(helpers.start_kong({
        database = "postgres",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "slow-query",
        nginx_worker_processes = 1,
        pg_pool_size = pool_size,
        pg_backlog = backlog_size,
        log_level = "info",
      }))
      client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
    end)

    it("results in query error too many waiting connect operations when pool and backlog sizes are exceeded", function()
      helpers.wait_timer("slow-query", true, "all-finish", 10)

      local delay = 4
      assert
        .with_timeout(10)
        -- wait for any ongoing query to finish before retrying
        .with_step(delay)
        .ignore_exceptions(true)
        .eventually(function()
          local ok = true
          for _ = 1, pool_size + backlog_size do
            local res = assert(client:send {
              method = "GET",
              path = "/slow-resource?prime=true&delay=" .. delay,
              headers = { ["Content-Type"] = "application/json" }
            })
            res:read_body()
            ok = ok and res.status == 204
          end
          return ok
        end)
        .is_truthy("expected both requests to succeed with empty pool and backlog")

      ngx.sleep(2)

      local res = assert(client:send {
        method = "GET",
        path = "/slow-resource?delay=-1",
        headers = { ["Content-Type"] = "application/json" }
      })
      local body = assert.res_status(500, res)
      local json = cjson.decode(body)
      assert.same({ error = "too many waiting connect operations" }, json)
    end)
  end)
end
