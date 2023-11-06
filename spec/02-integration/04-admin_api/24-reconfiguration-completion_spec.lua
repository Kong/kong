local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Admin API - Reconfiguration Completion -", function()

  local WORKER_STATE_UPDATE_FREQ = 1

  local admin_client
  local proxy_client

  local function run_tests()

    local res = admin_client:post("/plugins", {
      body = {
        name = "request-termination",
        config = {
          status_code = 200,
          body = "kong terminated the request",
        }
      },
      headers = { ["Content-Type"] = "application/json" },
    })
    assert.res_status(201, res)

    res = admin_client:post("/services", {
      body = {
        name = "test-service",
        url = "http://127.0.0.1",
      },
      headers = { ["Content-Type"] = "application/json" },
    })
    local body = assert.res_status(201, res)
    local service = cjson.decode(body)

    -- We're running the route setup in `eventually` to cover for the unlikely case that reconfiguration completes
    -- between adding the route and requesting the path through the proxy path.

    local next_path do
      local path_suffix = 0
      function next_path()
        path_suffix = path_suffix + 1
        return "/" .. tostring(path_suffix)
      end
    end

    local service_path
    local kong_transaction_id

    assert.eventually(function()
      service_path = next_path()

      res = admin_client:post("/services/" .. service.id .. "/routes", {
        body = {
          paths = { service_path }
        },
        headers = { ["Content-Type"] = "application/json" },
      })
      assert.res_status(201, res)
      kong_transaction_id = res.headers['x-kong-transaction-id']
      assert.is_string(kong_transaction_id)

      res = proxy_client:get(service_path,
              {
                headers = {
                  ["X-If-Kong-Transaction-Id"] = kong_transaction_id
                }
              })
      assert.res_status(503, res)
      assert.equals("pending", res.headers['x-kong-reconfiguration-status'])
      local retry_after = tonumber(res.headers['retry-after'])
      ngx.sleep(retry_after)
    end)
            .has_no_error()

    assert.eventually(function()
      res = proxy_client:get(service_path,
              {
                headers = {
                  ["X-If-Kong-Transaction-Id"] = kong_transaction_id
                }
              })
      body = assert.res_status(200, res)
      assert.equals("kong terminated the request", body)
    end)
            .has_no_error()
  end

  describe("#traditional mode -", function()
    lazy_setup(function()
      helpers.get_db_utils()
      assert(helpers.start_kong({
        worker_consistency = "eventual",
        worker_state_update_frequency = WORKER_STATE_UPDATE_FREQ,
      }))
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    teardown(function()
      if admin_client then
        admin_client:close()
      end
      if proxy_client then
        proxy_client:close()
      end
      helpers.stop_kong()
    end)

    it("rejects proxy requests if worker state has not been updated yet", run_tests)
  end)

  describe("#hybrid mode -", function()
    lazy_setup(function()
      helpers.get_db_utils()

      assert(helpers.start_kong({
        role = "control_plane",
        database = "postgres",
        prefix = "cp",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        cluster_listen = "127.0.0.1:9005",
        cluster_telemetry_listen = "127.0.0.1:9006",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      assert(helpers.start_kong({
        role = "data_plane",
        database = "off",
        prefix = "dp",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        cluster_control_plane = "127.0.0.1:9005",
        cluster_telemetry_endpoint = "127.0.0.1:9006",
        proxy_listen = "0.0.0.0:9002",
      }))
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client("127.0.0.1", 9002)
    end)

    teardown(function()
      if admin_client then
        admin_client:close()
      end
      if proxy_client then
        proxy_client:close()
      end
      helpers.stop_kong("dp")
      helpers.stop_kong("cp")
    end)

    it("rejects proxy requests if worker state has not been updated yet", run_tests)
  end)
end)
