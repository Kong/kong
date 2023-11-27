local helpers = require "spec.helpers"
local cjson = require "cjson"

local function get_log(typ, n)
  local entries
  helpers.wait_until(function()
    local client = assert(helpers.http_client(
            helpers.mock_upstream_host,
            helpers.mock_upstream_port
    ))
    local res = client:get("/read_log/" .. typ, {
      headers = {
        Accept = "application/json"
      }
    })
    local raw = assert.res_status(200, res)
    local body = cjson.decode(raw)

    entries = body.entries
    return #entries > 0
  end, 10)
  if n then
    assert(#entries == n, "expected " .. n .. " log entries, but got " .. #entries)
  end
  return entries
end

describe("Admin API - Reconfiguration Completion -", function()

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
        url = helpers.mock_upstream_url,
      },
      headers = { ["Content-Type"] = "application/json" },
    })
    local body = assert.res_status(201, res)
    local service = cjson.decode(body)

    -- We're running the route setup in `eventually` to cover for the unlikely case that reconfiguration completes
    -- between adding the route and requesting the path through the proxy path.

    local next_path_suffix do
      local path_suffix = 0
      function next_path_suffix()
        path_suffix = path_suffix + 1
        return tostring(path_suffix)
      end
    end

    local path_suffix
    local service_path
    local kong_transaction_id

    assert.eventually(function()
      path_suffix = next_path_suffix()
      service_path = "/" .. path_suffix

      res = admin_client:post("/services/" .. service.id .. "/routes", {
        body = {
          paths = { service_path }
        },
        headers = { ["Content-Type"] = "application/json" },
      })
      body = assert.res_status(201, res)
      local route = cjson.decode(body)

      kong_transaction_id = res.headers['kong-test-transaction-id']
      assert.is_string(kong_transaction_id)

      res = admin_client:post("/routes/" .. route.id .. "/plugins", {
        body = {
          name = "http-log",
          config = {
            http_endpoint = "http://" .. helpers.mock_upstream_host
                    .. ":"
                    .. helpers.mock_upstream_port
                    .. "/post_log/reconf" .. path_suffix
          }
        },
        headers = { ["Content-Type"] = "application/json" },
      })
      assert.res_status(201, res)

      kong_transaction_id = res.headers['kong-test-transaction-id']
      assert.is_string(kong_transaction_id)

      res = proxy_client:get(service_path,
              {
                headers = {
                  ["If-Kong-Test-Transaction-Id"] = kong_transaction_id
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
                  ["If-Kong-Test-Transaction-Id"] = kong_transaction_id
                }
              })
      body = assert.res_status(200, res)
      assert.equals("kong terminated the request", body)
    end)
            .has_no_error()

    get_log("reconf" .. path_suffix, 1)

  end

  describe("#traditional mode -", function()
    lazy_setup(function()
      helpers.get_db_utils()
      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
        db_update_frequency = 0.05,
        db_cache_neg_ttl = 0.01,
        worker_state_update_frequency = 0.1,
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
        db_update_frequency = 0.05,
        db_cache_neg_ttl = 0.01,
        worker_consistency = "eventual",
        worker_state_update_frequency = 0.1,
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
        db_update_frequency = 0.05,
        db_cache_neg_ttl = 0.01,
        worker_state_update_frequency = 0.1,
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
