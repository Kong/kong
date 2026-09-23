local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Reconfiguration completion detection helper", function()

  local STATE_UPDATE_FREQUENCY = .2

  local admin_client
  local proxy_client

  local function helper_tests(make_proxy_client)
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
    local body = assert.res_status(201, res)
    local request_termination_plugin_id = cjson.decode(body).id

    res = admin_client:post("/services", {
      body = {
        name = "test-service",
        url = "http://127.0.0.1",
      },
      headers = { ["Content-Type"] = "application/json" },
    })
    body = assert.res_status(201, res)
    local service = cjson.decode(body)

    local path = "/foo-barak"

    res = admin_client:post("/services/" .. service.id .. "/routes", {
      body = {
        paths = { path }
      },
      headers = { ["Content-Type"] = "application/json" },
    })
    assert.res_status(201, res)

    res = proxy_client:get(path)
    body = assert.res_status(200, res)
    assert.equals("kong terminated the request", body)

    res = admin_client:patch("/plugins/" .. request_termination_plugin_id, {
      body = {
        config = {
          status_code = 404,
          body = "kong terminated the request with 404",
        }
      },
      headers = { ["Content-Type"] = "application/json" },
    })
    assert.res_status(200, res)

    res = proxy_client:get(path)
    body = assert.res_status(404, res)
    assert.equals("kong terminated the request with 404", body)

    local second_admin_client = helpers.admin_client()
    admin_client:synchronize_sibling(second_admin_client)

    res = second_admin_client:patch("/plugins/" .. request_termination_plugin_id, {
      body = {
        config = {
          status_code = 405,
          body = "kong terminated the request with 405",
        }
      },
      headers = { ["Content-Type"] = "application/json" },
    })
    assert.res_status(200, res)

    local second_proxy_client = make_proxy_client()
    proxy_client:synchronize_sibling(second_proxy_client)

    res = second_proxy_client:get(path)
    body = assert.res_status(405, res)
    assert.equals("kong terminated the request with 405", body)
  end

  describe("#traditional mode", function()

    local function make_proxy_client()
      return helpers.proxy_client()
    end

    lazy_setup(function()
      helpers.get_db_utils()
      assert(helpers.start_kong({
        plugins = "bundled,reconfiguration-completion",
        worker_consistency = "eventual",
        worker_state_update_frequency = STATE_UPDATE_FREQUENCY,
      }))
      proxy_client, admin_client = helpers.make_synchronized_clients()
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

    it('', function () helper_tests(make_proxy_client) end)
  end)

  describe("#hybrid mode", function()

    local function make_proxy_client()
      return helpers.proxy_client("127.0.0.1", 9002)
    end

    lazy_setup(function()
      helpers.get_db_utils()

      assert(helpers.start_kong({
        plugins = "bundled,reconfiguration-completion",
        role = "control_plane",
        database = "postgres",
        prefix = "cp",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        cluster_listen = "127.0.0.1:9005",
        cluster_telemetry_listen = "127.0.0.1:9006",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        db_update_frequency = STATE_UPDATE_FREQUENCY,
      }))

      assert(helpers.start_kong({
        plugins = "bundled,reconfiguration-completion",
        role = "data_plane",
        database = "off",
        prefix = "dp",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        cluster_control_plane = "127.0.0.1:9005",
        cluster_telemetry_endpoint = "127.0.0.1:9006",
        proxy_listen = "0.0.0.0:9002",
        worker_state_update_frequency = STATE_UPDATE_FREQUENCY,
      }))
      proxy_client, admin_client = helpers.make_synchronized_clients({ proxy_client = make_proxy_client() })
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

    it('', function () helper_tests(make_proxy_client) end)
  end)
end)
