local helpers = require "spec.helpers"
local cjson = require "cjson"
local kong = kong

for _, strategy in helpers.all_strategies() do
  describe("Status API - with strategy #" .. strategy, function()
    local client

    lazy_setup(function()
      helpers.get_db_utils(strategy, {}) -- runs migrations
      assert(helpers.start_kong {
        status_listen = "127.0.0.1:9500",
        plugins = "admin-api-method",
        database = strategy,
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    describe("core", function()
      it("/status returns status info with blank configuration_hash (declarative config) or without it (db mode)", function()
        client = helpers.http_client("127.0.0.1", 9500, 20000)
        local res = assert(client:send {
          method = "GET",
          path = "/status"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.server)

        assert.is_number(json.server.connections_accepted)
        assert.is_number(json.server.connections_active)
        assert.is_number(json.server.connections_handled)
        assert.is_number(json.server.connections_reading)
        assert.is_number(json.server.connections_writing)
        assert.is_number(json.server.connections_waiting)
        assert.is_number(json.server.total_requests)
        if strategy == "off" then
          assert.is_equal(string.rep("0", 32), json.configuration_hash) -- all 0 in DBLESS mode until configuration is applied
          assert.is_nil(json.database)

        else
          assert.is_nil(json.configuration_hash) -- not present in DB mode
          assert.is_table(json.database)
          assert.is_boolean(json.database.reachable)
        end
        client:close()
      end)

      if strategy == "off" then
        it("/status starts providing a config_hash once an initial configuration has been pushed in dbless mode #off", function()
          local admin_client = helpers.http_client("127.0.0.1", 9001)
          -- push an initial configuration so that a configuration_hash will be present
          local postres = assert(admin_client:send {
            method = "POST",
            path = "/config",
            body = {
              config = [[
_format_version: "3.0"
services:
- name: example-service
  url: http://example.test
              ]],
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(201, postres)
          admin_client:close()

          client = helpers.http_client("127.0.0.1", 9500, 20000)
          local res = assert(client:send {
            method = "GET",
            path = "/status"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.is_nil(json.database)
          assert.is_table(json.server)
          assert.is_number(json.server.connections_accepted)
          assert.is_number(json.server.connections_active)
          assert.is_number(json.server.connections_handled)
          assert.is_number(json.server.connections_reading)
          assert.is_number(json.server.connections_writing)
          assert.is_number(json.server.connections_waiting)
          assert.is_number(json.server.total_requests)
          assert.is_string(json.configuration_hash)
          assert.equal(32, #json.configuration_hash)
          client:close()
        end)
      end
    end)

    describe("plugins", function()
      it("can add endpoints", function()
        client = helpers.http_client("127.0.0.1", 9500, 20000)
        local res = assert(client:send {
          method = "GET",
          path = "/hello"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(json, { hello = "from status api" })
        client:close()
      end)
    end)
  end)

  describe("Status API - with strategy #" .. strategy .. "and enforce_rbac=on", function()
    local client

    lazy_setup(function()
      helpers.get_db_utils(strategy, {}) -- runs migrations
      assert(helpers.start_kong {
        status_listen = "127.0.0.1:9500",
        plugins = "admin-api-method",
        database = strategy,
        enforce_rbac = "on",
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    describe("core", function()
      it("/status returns status info", function()
        client = helpers.http_client("127.0.0.1", 9500, 20000)
        local res = assert(client:send {
          method = "GET",
          path = "/status"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.server)

        if strategy == "off" then
          assert.is_nil(json.database)

        else
          assert.is_table(json.database)
          assert.is_boolean(json.database.reachable)
        end

        assert.is_number(json.server.connections_accepted)
        assert.is_number(json.server.connections_active)
        assert.is_number(json.server.connections_handled)
        assert.is_number(json.server.connections_reading)
        assert.is_number(json.server.connections_writing)
        assert.is_number(json.server.connections_waiting)
        assert.is_number(json.server.total_requests)
        client:close()
      end)
    end)

    describe("plugins", function()
      it("can add endpoints", function()
        client = helpers.http_client("127.0.0.1", 9500, 20000)
        local res = assert(client:send {
          method = "GET",
          path = "/hello"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(json, { hello = "from status api" })
        client:close()
      end)
    end)
  end)
end

for _, strategy in helpers.each_strategy() do
  describe("#db Status API DB-mode [#" .. strategy .. "#] with DB down", function()
    local custom_prefix = helpers.test_conf.prefix.."2"

    local status_api_port = helpers.get_available_port()
    local stream_proxy_port = helpers.get_available_port()

    local bp
    local status_client

    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, nil, {'prometheus'})

      local db_service = bp.services:insert{
        protocol = "tcp",
        host = kong.configuration.pg_host,
        port = kong.configuration.pg_port,
      }

      bp.routes:insert{
        protocols = { "tcp" },
        sources = {
          { ip = "0.0.0.0/0" },
        },
        destinations = {
          { ip = "127.0.0.1", port = stream_proxy_port },
        },
        service = { id = db_service.id },
      }

      assert(helpers.start_kong({
        database = strategy,
        stream_listen = "127.0.0.1:" .. stream_proxy_port,
        nginx_worker_processes = 1,
      }))

      assert(helpers.start_kong({
        database = strategy,
        pg_host = "127.0.0.1",
        pg_port = stream_proxy_port,
        plugins = "bundled,prometheus",
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
        admin_listen = "off",
        proxy_listen = "off",
        stream_listen = "off",
        status_listen = "127.0.0.1:" .. status_api_port,
        status_access_log = "logs/status_access.log",
        status_error_log = "logs/status_error.log",
        prefix = custom_prefix,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      helpers.stop_kong(custom_prefix)
    end)

    before_each(function()
      -- pg_timeout 5s
      status_client = assert(helpers.http_client("127.0.0.1", status_api_port, 20000))
    end)

    after_each(function()
      if status_client then status_client:close() end
    end)

    it("returns 200 but marks database unreachable", function()
      local res = assert(status_client:send {
        method  = "GET",
        path    = "/metrics",
      })
      local body = assert.res_status(200, res)
      assert.matches('kong_datastore_reachable 1', body, nil, true)

      local res = assert(status_client:send {
        method  = "GET",
        path    = "/status",
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      if strategy == "off" then
        assert.is_nil(json.database)
      else
        assert.is_true(json.database.reachable)
      end

      assert(helpers.stop_kong())

      local res = assert(status_client:send {
        method  = "GET",
        path    = "/metrics",
      })
      local body = assert.res_status(200, res)
      assert.matches('kong_datastore_reachable 0', body, nil, true)

      local res = assert(status_client:send {
        method  = "GET",
        path    = "/status",
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      if strategy == "off" then
        assert.is_nil(json.database)
      else
        assert.is_falsy(json.database.reachable)
      end
    end)
  end)
end

for _, strategy in helpers.all_strategies() do
  describe("Status API - with strategy #" .. strategy, function()
    local h2_client

    lazy_setup(function()
      helpers.get_db_utils(strategy, {}) -- runs migrations
      assert(helpers.start_kong {
        status_listen = "127.0.0.1:9500 ssl http2",
        plugins = "admin-api-method",
        database = strategy,
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("supports HTTP/2 #test", function()
      h2_client = helpers.http2_client("127.0.0.1", 9500, true)
      local res, headers = assert(h2_client {
        headers = {
          [":method"] = "GET",
          [":path"] = "/status",
          [":authority"] = "127.0.0.1:9500",
        },
      })
      local json = cjson.decode(res)

      assert.equal('200', headers:get ":status")

      if strategy == "off" then
        assert.is_nil(json.database)

      else
        assert.is_table(json.database)
        assert.is_boolean(json.database.reachable)
      end

      assert.is_number(json.server.connections_accepted)
      assert.is_number(json.server.connections_active)
      assert.is_number(json.server.connections_handled)
      assert.is_number(json.server.connections_reading)
      assert.is_number(json.server.connections_writing)
      assert.is_number(json.server.connections_waiting)
      assert.is_number(json.server.total_requests)
    end)
  end)
end
