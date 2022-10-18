local constants = require "kong.constants"
local helpers = require "spec.helpers"
local websocket_client = require "resty.websocket.client"
local cjson = require "cjson"


local MESSAGE = "echo, ping, pong. echo, ping, pong. echo, ping, pong.\n"


local function websocket_send_text_and_get_echo(uri)
  local payload = { message = "hello websocket" }
  local wc = assert(websocket_client:new())
  assert(wc:connect(uri))

  assert(wc:send_text(cjson.encode(payload)))
  local frame, typ, err = wc:recv_frame()
  assert.is_nil(wc.fatal)
  assert(frame, err)
  assert.equal("text", typ)
  assert.same(payload, cjson.decode(frame))

  assert(wc:send_close())
end


for _, strategy in helpers.each_strategy() do

  -- Might need to be marked as flaky because it may require an arbitrary high port?
  describe("anonymous reports in Admin API #" .. strategy, function()
    local dns_hostsfile
    local reports_server

    local reports_send_ping = function(opts)
      ngx.sleep(0.01) -- hand over the CPU so other threads can do work (processing the sent data)
      local admin_client = helpers.admin_client()
      local opts = opts or {}
      local port = opts.port or nil

      local res = admin_client:post("/reports/send-ping" .. (port and "?port=" .. port or ""))
      assert.response(res).has_status(200)
      admin_client:close()
    end

    local reports_send_stream_ping = function()
      ngx.sleep(0.01) -- hand over the CPU so other threads can do work (processing the sent data)

      local tcp = ngx.socket.tcp()
      assert(tcp:connect(helpers.get_proxy_ip(false), 19001))

      local body = assert(tcp:receive("*a"))
      assert.equal("ok", body)

      tcp:close()
    end

    lazy_setup(function()
      dns_hostsfile = assert(os.tmpname() .. ".hosts")
      local fd = assert(io.open(dns_hostsfile, "wb"))
      assert(fd:write("127.0.0.1 " .. constants.REPORTS.ADDRESS))
      assert(fd:close())

      local bp = assert(helpers.get_db_utils(strategy, {
        "services",
        "routes",
        "plugins",
        "certificates",
        "snis",
      }, { "reports-api" }))

      local http_srv = assert(bp.services:insert {
        name = "mock-service",
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
      })

      bp.routes:insert({ service = http_srv,
                         protocols = { "http" },
                         hosts = { "http-service.test" } })

      bp.routes:insert({ service = http_srv,
                         protocols = { "https" },
                         hosts = { "https-service.test" } })

      local grpc_srv = bp.services:insert({
        name = "grpc",
        url = helpers.grpcbin_url,
      })

      bp.routes:insert({
        service = grpc_srv,
        protocols = { "grpc" },
        hosts = { "grpc" },
      })

      local grpcs_srv = bp.services:insert({
        name = "grpcs",
        url = helpers.grpcbin_ssl_url,
      })

      bp.routes:insert({
        service = grpcs_srv,
        protocols = { "grpcs" },
        hosts = { "grpcs" },
      })

      local ws_srv = bp.services:insert({
        name = "ws",
        path = "/ws",
      })

      bp.routes:insert({
        service = ws_srv,
        protocols = { "http" },
        paths = { "/up-ws" },
        strip_path = true,
      })

      local tcp_srv = bp.services:insert({
        name = "tcp",
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_stream_port,
        protocol = "tcp"
      })

      bp.routes:insert {
        destinations = {
          { port = 19000, },
        },
        protocols = {
          "tcp",
        },
        service = tcp_srv,
      }

      local tls_srv = bp.services:insert({
        name = "tls",
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_stream_ssl_port,
        protocol = "tls"
      })

      bp.routes:insert {
        destinations = {
          { port = 19443, },
        },
        protocols = {
          "tls",
        },
        service = tls_srv,
      }

      local reports_srv = bp.services:insert({
        name = "reports-srv",
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_stream_port,
        protocol = "tcp"
      })

      bp.routes:insert {
        destinations = {
          { port = 19001, },
        },
        protocols = {
          "tcp",
        },
        service = reports_srv,
      }

      bp.plugins:insert({
        name = "reports-api",
        service = { id = reports_srv.id },
        protocols = { "tcp" },
        config = {}
      })

      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
        database = strategy,
        dns_hostsfile = dns_hostsfile,
        anonymous_reports = true,
        plugins = "reports-api",
        stream_listen = helpers.get_proxy_ip(false) .. ":19000," ..
                        helpers.get_proxy_ip(false) .. ":19001," ..
                        helpers.get_proxy_ip(true)  .. ":19443 ssl",

      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      os.remove(dns_hostsfile)
    end)


    before_each(function()
      reports_server = helpers.tcp_server(constants.REPORTS.STATS_TLS_PORT, {tls=true})
    end)

    it("reports http requests", function()
      local proxy_client = assert(helpers.proxy_client())
      local res = proxy_client:get("/", {
        headers = { host  = "http-service.test" }
      })
      assert.response(res).has_status(200)

      reports_send_ping({port=constants.REPORTS.STATS_TLS_PORT})

      local _, reports_data = assert(reports_server:join())
      assert.match("requests=1", reports_data)
      assert.match("http_reqs=1", reports_data)
      assert.match("https_reqs=0", reports_data)
      assert.match("h2c_reqs=0", reports_data)
      assert.match("h2_reqs=0", reports_data)
      assert.match("grpc_reqs=0", reports_data)
      assert.match("grpcs_reqs=0", reports_data)
      assert.match("ws_reqs=0", reports_data)
      assert.match("wss_reqs=0", reports_data)

      proxy_client:close()
    end)

    it("reports https requests", function()
      local proxy_ssl_client = assert(helpers.proxy_ssl_client())
      local res = proxy_ssl_client:get("/", {
        headers = { host  = "https-service.test" }
      })
      assert.response(res).has_status(200)

      reports_send_ping({port=constants.REPORTS.STATS_TLS_PORT})

      local _, reports_data = assert(reports_server:join())
      assert.match("requests=1", reports_data)
      assert.match("http_reqs=0", reports_data)
      assert.match("https_reqs=1", reports_data)
      assert.match("h2c_reqs=0", reports_data)
      assert.match("h2_reqs=0", reports_data)
      assert.match("grpc_reqs=0", reports_data)
      assert.match("grpcs_reqs=0", reports_data)
      assert.match("ws_reqs=0", reports_data)
      assert.match("wss_reqs=0", reports_data)

      proxy_ssl_client:close()
    end)

    it("reports h2c requests", function()
      local h2c_client = assert(helpers.proxy_client_h2c())
      local body, headers = h2c_client({
        headers = { [":authority"] = "http-service.test" }
      })

      assert.equal(200, tonumber(headers:get(":status")))
      assert.is_not_nil(body)

      reports_send_ping({port=constants.REPORTS.STATS_TLS_PORT})

      local _, reports_data = assert(reports_server:join())
      assert.match("requests=1", reports_data)
      assert.match("http_reqs=0", reports_data)
      assert.match("https_reqs=0", reports_data)
      assert.match("h2c_reqs=1", reports_data)
      assert.match("h2_reqs=0", reports_data)
      assert.match("grpc_reqs=0", reports_data)
      assert.match("grpcs_reqs=0", reports_data)
      assert.match("ws_reqs=0", reports_data)
      assert.match("wss_reqs=0", reports_data)
    end)

    it("reports h2 requests", function()
      local h2_client = assert(helpers.proxy_client_h2())
      local body, headers = h2_client({
        headers = { [":authority"] = "https-service.test" }
      })

      assert.equal(200, tonumber(headers:get(":status")))
      assert.is_not_nil(body)

      reports_send_ping({port=constants.REPORTS.STATS_TLS_PORT})

      local _, reports_data = assert(reports_server:join())
      assert.match("requests=1", reports_data)
      assert.match("http_reqs=0", reports_data)
      assert.match("https_reqs=0", reports_data)
      assert.match("h2c_reqs=0", reports_data)
      assert.match("h2_reqs=1", reports_data)
      assert.match("grpc_reqs=0", reports_data)
      assert.match("grpcs_reqs=0", reports_data)
      assert.match("ws_reqs=0", reports_data)
      assert.match("wss_reqs=0", reports_data)
    end)


    it("reports grpc requests", function()
      local grpc_client = helpers.proxy_client_grpc()
      assert(grpc_client({
        service = "hello.HelloService.SayHello",
        opts = {
          ["-authority"] = "grpc",
        },
      }))

      reports_send_ping({port=constants.REPORTS.STATS_TLS_PORT})

      local _, reports_data = assert(reports_server:join())
      assert.match("requests=1", reports_data)
      assert.match("http_reqs=0", reports_data)
      assert.match("https_reqs=0", reports_data)
      assert.match("h2c_reqs=0", reports_data)
      assert.match("h2_reqs=0", reports_data)
      assert.match("grpc_reqs=1", reports_data)
      assert.match("grpcs_reqs=0", reports_data)
      assert.match("ws_reqs=0", reports_data)
      assert.match("wss_reqs=0", reports_data)
    end)

    it("reports grpcs requests", function()
      local grpcs_client = assert(helpers.proxy_client_grpcs())
      grpcs_client({
        service = "hello.HelloService.SayHello",
        opts = {
          ["-authority"] = "grpcs",
        },
      })

      reports_send_ping({port=constants.REPORTS.STATS_TLS_PORT})

      local _, reports_data = assert(reports_server:join())
      assert.match("requests=1", reports_data)
      assert.match("http_reqs=0", reports_data)
      assert.match("https_reqs=0", reports_data)
      assert.match("h2c_reqs=0", reports_data)
      assert.match("h2_reqs=0", reports_data)
      assert.match("grpc_reqs=0", reports_data)
      assert.match("grpcs_reqs=1", reports_data)
      assert.match("ws_reqs=0", reports_data)
      assert.match("wss_reqs=0", reports_data)
    end)

    it("reports ws requests", function()
      websocket_send_text_and_get_echo("ws://" .. helpers.get_proxy_ip(false) ..
                                       ":" .. helpers.get_proxy_port(false) .. "/up-ws")

      reports_send_ping({port=constants.REPORTS.STATS_TLS_PORT})

      local _, reports_data = assert(reports_server:join())
      assert.match("requests=1", reports_data)
      assert.match("http_reqs=0", reports_data)
      assert.match("https_reqs=0", reports_data)
      assert.match("h2c_reqs=0", reports_data)
      assert.match("h2_reqs=0", reports_data)
      assert.match("grpc_reqs=0", reports_data)
      assert.match("grpcs_reqs=0", reports_data)
      assert.match("ws_reqs=1", reports_data)
      assert.match("wss_reqs=0", reports_data)
    end)

    it("reports wss requests", function()
      websocket_send_text_and_get_echo("wss://" .. helpers.get_proxy_ip(true) ..
                                       ":" .. helpers.get_proxy_port(true) .. "/up-ws")

      reports_send_ping({port=constants.REPORTS.STATS_TLS_PORT})

      local _, reports_data = assert(reports_server:join())
      assert.match("requests=1", reports_data)
      assert.match("http_reqs=0", reports_data)
      assert.match("https_reqs=0", reports_data)
      assert.match("h2c_reqs=0", reports_data)
      assert.match("h2_reqs=0", reports_data)
      assert.match("grpc_reqs=0", reports_data)
      assert.match("grpcs_reqs=0", reports_data)
      assert.match("ws_reqs=0", reports_data)
      assert.match("wss_reqs=1", reports_data)
    end)

    pending("#stream reports tcp streams", function()
      local tcp = ngx.socket.tcp()
      assert(tcp:connect(helpers.get_proxy_ip(false), 19000))

      assert(tcp:send(MESSAGE))

      local body = assert(tcp:receive("*a"))
      assert.equal(MESSAGE, body)

      tcp:close()

      reports_send_stream_ping()

      local _, reports_data = assert(reports_server:join())
      assert.match("streams=1", reports_data)
      assert.match("tcp_streams=1", reports_data)
      assert.match("tls_streams=0", reports_data)
    end)

    pending("#stream reports tls streams", function()
      local tcp = ngx.socket.tcp()

      assert(tcp:connect(helpers.get_proxy_ip(true), 19443))

      assert(tcp:sslhandshake(nil, "this-is-needed.test", false))

      assert(tcp:send(MESSAGE))

      local body = assert(tcp:receive("*a"))
      assert.equal(MESSAGE, body)

      tcp:close()

      reports_send_stream_ping()

      local _, reports_data = assert(reports_server:join())
      assert.match("streams=2", reports_data)
      assert.match("tcp_streams=1", reports_data) -- it counts the stream request for the ping
      assert.match("tls_streams=1", reports_data)
    end)

    it("does not log NGINX-produced errors", function()
      local proxy_client = assert(helpers.proxy_client())
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/",
        headers = {
          ["X-Large"] = string.rep("a", 2^10 * 10), -- default large_client_header_buffers is 8k
        }
      })

      -- send a ping so the tcp server shutdown cleanly and not with a timeout.
      reports_send_ping({port=constants.REPORTS.STATS_TLS_PORT})

      assert.res_status(400, res)
      proxy_client:close()

      assert.errlog()
            .has.no.line([[could not determine log suffix]], true)
    end)

    it("reports route statistics", function()
      local proxy_client = assert(helpers.proxy_client())
      local res = proxy_client:get("/", {
        headers = { host  = "http-service.test" }
      })
      assert.response(res).has_status(200)

      reports_send_ping({port=constants.REPORTS.STATS_TLS_PORT})

      local _, reports_data = assert(reports_server:join())

      assert.match([["headers":0]], reports_data)
      assert.match([["routes":5]], reports_data)
      assert.match([["http":3]], reports_data)
      assert.match([["grpc":2]], reports_data)
      assert.match([["stream":0]], reports_data)
      assert.match([["tls_passthrough":0]], reports_data)
      assert.match([["flavor":"traditional_compatible"]], reports_data)
      assert.match([["paths":1]], reports_data)
      assert.match([["regex_routes":0]], reports_data)
      assert.match([["v1":0]], reports_data)
      assert.match([["v0":5]], reports_data)
      proxy_client:close()
    end)

    if strategy ~= "off" then
      it("reports route statistics after change", function()
        local admin = helpers.admin_client()
        -- any other route will fail because we are ... routing all traffic to localhost
        assert.res_status(201, admin:send({
          method = "POST",
          path = "/services",
          body = {
            name = "test",
            url = "http://localhost:9001/services/",
            path = "/",
          },
          headers = { ["Content-Type"] = "application/json" },
        }))
        assert.res_status(201, admin:send({
          method = "POST",
          path = "/services/test/routes",
          body = {
            protocols = { "http" },
            headers = { ["x-test"] = { "test" } },
            paths = { "~/test", "/normal" },
            preserve_host = false,
            path_handling = "v1",
          },
          headers = { ["Content-Type"] = "application/json" },
        }))

        local proxy_client = assert(helpers.proxy_client())
        helpers.pwait_until(function()
          local res = proxy_client:get("/test", {
            headers = { ["x-test"] = "test", host = "http-service2.test" }
          })
          assert.response(res).has_status(200)
        end, 1000)

        reports_send_ping({port=constants.REPORTS.STATS_TLS_PORT})

        local _, reports_data = assert(reports_server:join())

        assert.match([["headers":1]], reports_data)
        assert.match([["routes":6]], reports_data)
        assert.match([["http":4]], reports_data)
        assert.match([["grpc":2]], reports_data)
        assert.match([["stream":0]], reports_data)
        assert.match([["tls_passthrough":0]], reports_data)
        assert.match([["flavor":"traditional_compatible"]], reports_data)
        assert.match([["paths":3]], reports_data)
        assert.match([["regex_routes":1]], reports_data)
        assert.match([["v1":1]], reports_data)
        assert.match([["v0":5]], reports_data)
        proxy_client:close()
      end)
    end
  end)
end
