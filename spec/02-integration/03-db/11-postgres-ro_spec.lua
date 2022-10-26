local helpers = require "spec.helpers"
local cjson = require "cjson.safe"


for _, strategy in helpers.each_strategy() do
  local postgres_only = strategy == "postgres" and describe or pending

  postgres_only("postgres readonly connection", function()
    local proxy_client, admin_client

    lazy_setup(function()
      helpers.get_db_utils(strategy, {
        "routes",
        "services",
      }) -- runs migrations

      assert(helpers.start_kong({
        database = strategy,
        pg_ro_host = helpers.test_conf.pg_host,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if admin_client then admin_client:close() end
      if proxy_client then proxy_client:close() end
      helpers.stop_kong()
    end)

    describe("proxy and admin API works", function()
      local route_id

      it("can change and retrieve config using Admin API", function()
        local res = assert(admin_client:post("/services", {
          body = { name = "mock-service", url = "https://127.0.0.1:15556/request", },
          headers = {["Content-Type"] = "application/json"}
        }))
        assert.res_status(201, res)

        res = assert(admin_client:get("/services/mock-service"))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equals(json.path, "/request")

        res = assert(admin_client:post("/services/mock-service/routes", {
          body = { paths = { "/" }, },
          headers = {["Content-Type"] = "application/json"}
        }))
        body = assert.res_status(201, res)
        json = cjson.decode(body)

        route_id = json.id

        helpers.wait_until(function()
          res = assert(proxy_client:send({
            method  = "GET",
            path    = "/",
          }))

          return pcall(function()
            assert.res_status(200, res)
          end)
        end, 10)
      end)

      it("cache invalidation works on config change", function()
        local res = assert(admin_client:send({
          method = "DELETE",
          path   = "/routes/" .. route_id,
        }))
        assert.res_status(204, res)

        helpers.wait_until(function()
          res = assert(proxy_client:send({
            method  = "GET",
            path    = "/",
          }))

          return pcall(function()
            assert.res_status(404, res)
          end)
        end, 10)
      end)
    end)
  end)

  postgres_only("postgres bad readonly connection", function()
    local proxy_client, admin_client

    lazy_setup(function()
      helpers.get_db_utils(strategy, {
        "routes",
        "services",
      }) -- runs migrations

      assert(helpers.start_kong({
        worker_consistency = "strict",
        database = strategy,
        pg_ro_host = helpers.test_conf.pg_host,
        pg_ro_port = 9090, -- connection refused
      }))

      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if admin_client then admin_client:close() end
      if proxy_client then proxy_client:close() end
      helpers.stop_kong()
    end)

    describe("read only operation breaks and read write operation works", function()
      it("admin API bypasses readonly connection but proxy doesn't", function()
        local res = assert(admin_client:post("/services", {
          body = { name = "mock-service", url = "https://127.0.0.1:15556/request", },
          headers = {["Content-Type"] = "application/json"}
        }))
        assert.res_status(201, res)

        res = assert(admin_client:get("/services/mock-service"))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equals(json.path, "/request")

        res = assert(admin_client:post("/services/mock-service/routes", {
          body = { paths = { "/" }, },
          headers = {["Content-Type"] = "application/json"}
        }))
        assert.res_status(201, res)

        helpers.wait_until(function()
          res = assert(proxy_client:send({
            method  = "GET",
            path    = "/",
          }))

          return pcall(function()
            assert.res_status(404, res)
            assert.logfile().has.line("get_updated_router(): could not rebuild router: " ..
                                  "could not load routes: [postgres] connection " ..
                                  "refused (stale router will be used)", true)
          end)
        end, 10)

      end)
    end)
  end)
end
