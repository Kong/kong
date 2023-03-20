-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson      = require "cjson"
local utils      = require "kong.tools.utils"
local helpers    = require "spec.helpers"
local pl_stringx = require "pl.stringx"
local ws         = require "spec-ee.fixtures.websocket"
local ee_helpers = require "spec-ee.helpers"

local TCP_PORT = helpers.get_available_port()
local UDP_PORT = helpers.get_available_port()
local LOGGLY_PORT = helpers.get_available_port()
local TIMEOUT = 30

for _, strategy in helpers.each_strategy() do
  describe("#websocket logging plugins [#" .. strategy .. "]", function()

    local uuid = utils.uuid()
    local plugins = {}
    local threads = {}
    local verify

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })

      local custom = {
        websockets = [[return "are fun"]],
      }

      local service = assert(bp.services:insert({
        name = "ws-test",
        protocol = "ws",
      }))

      local route = assert(bp.routes:insert({
        name = "ws-test",
        hosts = { "websocket.test" },
        protocols = { "ws", "wss" },
        service = service,
      }))

      do
        -- file-log
        plugins.file = assert(bp.plugins:insert({
          name = "file-log",
          route    = route,
          config   = {
            path   = os.tmpname(),
            reopen = true,
            custom_fields_by_lua = custom,
          },
        }))
      end


      do
        -- http-log
        local endpoint = helpers.mock_upstream_url .. "/post_log/http"
        plugins.http = assert(bp.plugins:insert({
          name     = "http-log",
          route    = route,
          config   = {
            custom_fields_by_lua = custom,
            http_endpoint = endpoint,
          },
        }))
      end

      do
        -- tcp-log
        plugins.tcp = assert(bp.plugins:insert {
          name     = "tcp-log",
          route    = route,
          config   = {
            host   = "127.0.0.1",
            port   = TCP_PORT,
            custom_fields_by_lua = custom,
          },
        })

        threads.tcp = helpers.tcp_server(TCP_PORT, {
          timeout = TIMEOUT,
        })
      end

      do
        -- udp-log
        plugins.udp = assert(bp.plugins:insert {
          route = { id = route.id },
          name     = "udp-log",
          config   = {
            host   = "127.0.0.1",
            port   = UDP_PORT,
            custom_fields_by_lua = custom,
          },
        })

        threads.udp = helpers.udp_server(UDP_PORT, nil, TIMEOUT)
      end

      do
        -- syslog
        plugins.syslog = assert(bp.plugins:insert {
          name     = "syslog",
          route = route,
          config   = {
            log_level              = "info",
            successful_severity    = "info",
            client_errors_severity = "info",
            server_errors_severity = "info",
            custom_fields_by_lua   = custom,
          },
        })
      end


      do
        -- loggly
        plugins.loggly = assert(bp.plugins:insert {
          name   = "loggly",
          route  = route,
          config = {
            host                = "127.0.0.1",
            port                = LOGGLY_PORT,
            key                 = "123456789",
            log_level           = "info",
            successful_severity = "warning",
            custom_fields_by_lua = custom,
          }
        })

        threads.loggly = helpers.udp_server(LOGGLY_PORT, nil, TIMEOUT)
      end


      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, { http_mock = { ws = ws.mock_upstream() } }))


      do
        -- Ensure that Kong is up+responsive and then truncate the error log.
        --
        -- This is done to ensure that no startup-related errors (like an expired
        -- license message) are caught when we check for errors later on.

        helpers.wait_until(function()
          local admin = helpers.admin_client()
          local res = admin:send({
            method = "GET",
            path = "/",
          })
          admin:close()
          return res and res.status == 200
        end)

        helpers.clean_logfile()

        -- On some systems os.tmpname() also creates the file. Ensure the file
        -- is created by the plugin instead (with the right permission).
        os.remove(plugins.file.config.path)
      end


      do
        local conn = ee_helpers.ws_proxy_client({
          host = "websocket.test",
          path = "/",
          headers = {
            ["x-log-id"] = uuid,
          },
          query = {
            id = uuid,
          },
        })

        -- sanity
        assert(conn:send_text("hi"))
        local data, typ, err = conn:recv_frame()
        assert.is_nil(err)
        assert.equals("text", typ)
        assert.equals("hi", data)
        assert(conn:send_close())
      end

      function verify(log)
        local req = assert.is_table(log.request, "missing 'request' field")
        local res = assert.is_table(log.response, "missing 'response' field")

        assert.equals("127.0.0.1",      log.client_ip,           "invalid client_ip")
        assert.equals(101,              res.status,              "invalid http response code")
        assert.equals("websocket.test", req.headers["host"],     "invalid host header")
        assert.equals(uuid,             req.headers["x-log-id"], "invalid x-log-id header")
        assert.equals(uuid,             req.querystring.id,      "invalid 'id' query arg")
        assert.equals(service.name,     log.service.name,        "invalid service name")
        assert.equals(route.name,       log.route.name,          "invalid route name")
        assert.equals("are fun",        log.websockets,          "invalid custom lua field")

        assert.logfile().has.no.line("\\[(error|alert|crit|emerg)\\]", false, 0.5)
      end
    end)

    lazy_teardown(function()
      for _, th in pairs(threads) do
        pcall(th.join, th)
      end

      helpers.stop_kong()
    end)

    it("file-log", function()
      local path = plugins.file.config.path

      helpers.wait_until(function()
        return helpers.path.exists(path)
           and helpers.path.getsize(path) > 0
      end, 10)

      local log = assert(helpers.file.read(path))
      log = cjson.decode(pl_stringx.strip(log):match("%b{}"))
      verify(log)
    end)

    it("http-log", function()
      local log
      local client = assert(helpers.http_client(helpers.mock_upstream_host,
                                                helpers.mock_upstream_port))

      helpers.wait_until(function()
        local res = client:get("/read_log/http", {
          headers = {
            Accept = "application/json"
          }
        })
        local raw = assert.res_status(200, res)
        log = cjson.decode(raw)

        return log
           and log.entries
           and #log.entries >= 1
      end, 10, 0.5)
      client:close()

      log = log.entries[1]

      verify(log)
    end)

    it("tcp-log", function()
      local ok, res = threads.tcp:join()
      threads.tcp = nil
      assert.True(ok)
      assert.is_string(res)

      local log = cjson.decode(res)
      verify(log)
    end)

    it("udp-log", function()
      local ok, res, err = threads.udp:join()
      threads.udp = nil
      assert.True(ok)
      assert.is_nil(err)
      assert.is_string(res)

      local log = cjson.decode(res)
      verify(log)
    end)

    it("loggly", function()
      local ok, res, err = threads.loggly:join()
      threads.loggly = nil
      assert.True(ok)
      assert.is_nil(err)
      assert.is_string(res)

      local json = assert(res:match("{.*}"))
      local log = cjson.decode(json)
      verify(log)
    end)
  end)
end
