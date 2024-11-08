local helpers = require "spec.helpers"
local http = require "resty.http"

local cp_status_port = helpers.get_available_port()
local dp_status_port = 8100

local function get_status_no_ssl_verify()
  local httpc = http.new()

  local ok, err = httpc:connect({
      scheme = "https",
      host = "127.0.0.1",
      port = dp_status_port,
      ssl_verify = false,
  })
  if not ok then
      return nil, err
  end

  local res, err = httpc:request({
      path = "/status/ready",
      headers = {
          ["Content-Type"] = "application/json",
      }
  })

  if not res then
    return nil, err
  end

  return res.status
end

for _, strategy in helpers.each_strategy() do
  if strategy ~= "off" then
    -- skip the "off" strategy, as dbless has its own test suite
    describe("kong unready with #" .. strategy .. " backend", function()
      lazy_setup(function()
        helpers.get_db_utils(strategy, {}) -- runs migrations

        assert(helpers.start_kong({
          database = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
          status_listen = "127.0.0.1:8100",
          nginx_main_worker_processes = 8,
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("should set Kong to 'unready'", function()
        helpers.wait_until(function()
          local http_client = helpers.http_client('127.0.0.1', dp_status_port)

          local res = http_client:send({
            method = "GET",
            path = "/status/ready",
          })

          local status = res and res.status
          http_client:close()
          if status == 200 then
            return true
          end
        end, 10)

        local ok, err, msg = helpers.kong_exec("unready", {
          prefix = helpers.test_conf.prefix,
        })
        assert.equal("", err)
        assert.equal("Kong's status successfully changed to 'unready'\n", msg)
        assert.equal(true, ok)

        helpers.wait_until(function()
          local http_client = helpers.http_client('127.0.0.1', dp_status_port)

          local res = http_client:send({
            method = "GET",
            path = "/status/ready",
          })

          local status = res and res.status
          http_client:close()
          if status == 503 then
            return true
          end
        end, 10)
      end)

    end)

    describe("Kong without a status listener", function()
      lazy_setup(function()
        helpers.get_db_utils(strategy, {}) -- runs migrations

        assert(helpers.start_kong({
          database = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("should return an error when trying to set 'unready' without a status listener", function()
        local ok, err, msg = helpers.kong_exec("unready", {
          prefix = helpers.test_conf.prefix,
        })
        assert.equal("", err)
        assert.equal("No status listeners found in configuration.\n", msg)
        assert.equal(true, ok)
      end)

    end)

    describe("Kong with SSL-enabled status listener", function()
      lazy_setup(function()
        helpers.get_db_utils(strategy, {}) -- runs migrations

        assert(helpers.start_kong({
          database = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
          status_listen = "127.0.0.1:8100 ssl",
          nginx_main_worker_processes = 8,
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("should set Kong to 'unready' with SSL-enabled status listener", function()
        helpers.wait_until(function()
          local status = get_status_no_ssl_verify()
          if status == 200 then
            return true
          end
        end, 10)

        local ok, err, msg = helpers.kong_exec("unready", {
          prefix = helpers.test_conf.prefix,
        })
        assert.equal("", err)
        assert.equal("Kong's status successfully changed to 'unready'\n", msg)
        assert.equal(true, ok)

        helpers.wait_until(function()
          local status = get_status_no_ssl_verify()
          if status == 503 then
            return true
          end
        end, 10)
      end)
    end)
  end
end

for _, strategy in helpers.each_strategy({"postgres"}) do
  describe("kong unready in hybrid mode #" .. strategy, function()
    local bp = helpers.get_db_utils(strategy, {
      "services",
    })

    -- insert some data to make sure the control plane is ready and send the configuration to dp
    -- so that `current_hash` of dp wouldn't be DECLARATIVE_EMPTY_CONFIG_HASH, so that dp would be ready
    assert(bp.services:insert {
      name = "example",
    })

    lazy_setup(function()
      assert(helpers.start_kong({
        role = "data_plane",
        database = "off",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        cluster_control_plane = "127.0.0.1:9005",
        proxy_listen = "127.0.0.1:9002",
        nginx_worker_processes = 8,
        status_listen = "127.0.0.1:" .. dp_status_port,
        prefix = "serve_dp",
        log_level = "info",
      }))

      assert(helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        database = strategy,
        prefix = "serve_cp",
        cluster_listen = "127.0.0.1:9005",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        status_listen = "127.0.0.1:" .. cp_status_port
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong("serve_dp")
      helpers.stop_kong("serve_cp")
    end)

    it("should set Kong to 'unready'", function()
      helpers.wait_until(function()
        local http_client = helpers.http_client('127.0.0.1', dp_status_port)

        local res = http_client:send({
          method = "GET",
          path = "/status/ready",
        })

        local status = res and res.status
        http_client:close()
        if status == 200 then
          return true
        end
      end, 10)

      -- set dp to unready
      local ok, err, msg = helpers.kong_exec("unready --prefix serve_dp", {
        prefix = helpers.test_conf.prefix,
        database = "off",
      })
      assert.equal("", err)
      assert.equal("Kong's status successfully changed to 'unready'\n", msg)
      assert.equal(true, ok)

      helpers.wait_until(function()
        local http_client = helpers.http_client('127.0.0.1', dp_status_port)

        local res = http_client:send({
          method = "GET",
          path = "/status/ready",
        })

        local status = res and res.status
        http_client:close()
        if status == 503 then
          return true
        end
      end, 10)

      -- set cp to unready
      local ok, err, msg = helpers.kong_exec("unready --prefix serve_cp", {
        prefix = helpers.test_conf.prefix,
      })
      assert.equal("", err)
      assert.equal("Kong's status successfully changed to 'unready'\n", msg)
      assert.equal(true, ok)

      helpers.wait_until(function()
        local http_client = helpers.http_client('127.0.0.1', cp_status_port)

        local res = http_client:send({
          method = "GET",
          path = "/status/ready",
        })

        local status = res and res.status
        http_client:close()
        if status == 503 then
          return true
        end
      end, 10)
    end)
  end)
end
