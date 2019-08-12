local constants = require "kong.constants"
local helpers = require "spec.helpers"
local websocket_client = require "resty.websocket.client"
local cjson = require "cjson"


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

    local reports_send_ping = function()
      ngx.sleep(0.01) -- hand over the CPU so other threads can do work (processing the sent data)
      local admin_client = helpers.admin_client()
      local res = admin_client:post("/reports/send-ping")
      assert.response(res).has_status(200)
      admin_client:close()
    end

    lazy_setup(function()
      dns_hostsfile = assert(os.tmpname())
      local fd = assert(io.open(dns_hostsfile, "w"))
      assert(fd:write("127.0.0.1 " .. constants.REPORTS.ADDRESS))
      assert(fd:close())
    end)

    lazy_teardown(function()
      os.remove(dns_hostsfile)
    end)

    before_each(function()
      reports_server = helpers.mock_reports_server()

      local bp = assert(helpers.get_db_utils(strategy, {
        "services",
        "routes"
      }))

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
        url = "grpc://localhost:15002",
      })
      bp.routes:insert({
        service = grpc_srv,
        protocols = { "grpc" },
        hosts = { "grpc" },
      })

      local grpcs_srv = bp.services:insert({
        name = "grpcs",
        url = "grpcs://localhost:15003",
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

      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
        database = strategy,
        dns_hostsfile = dns_hostsfile,
        anonymous_reports = "on",
        plugins = "reports-api",
      }))

    end)

    after_each(function()
      helpers.stop_kong()
      reports_server:stop() -- stop the reports server if it was not already stopped
    end)

    it("reports http requests", function()
      local proxy_client = assert(helpers.proxy_client())
      local res = proxy_client:get("/", {
        headers = { host  = "http-service.test" }
      })
      assert.response(res).has_status(200)

      reports_send_ping()
      local _, reports_data = assert(reports_server:stop())

      assert.same(1, #reports_data)
      assert.match("requests=1", reports_data[1])
      assert.match("http_reqs=1", reports_data[1])
      assert.match("https_reqs=0", reports_data[1])
      assert.match("grpc_reqs=0", reports_data[1])
      assert.match("grpcs_reqs=0", reports_data[1])
      assert.match("ws_reqs=0", reports_data[1])
      assert.match("wss_reqs=0", reports_data[1])

      proxy_client:close()
    end)

    it("reports https requests", function()
      local proxy_ssl_client = assert(helpers.proxy_ssl_client())
      local res = proxy_ssl_client:get("/", {
        headers = { host  = "https-service.test" }
      })
      assert.response(res).has_status(200)

      reports_send_ping()
      local _, reports_data = assert(reports_server:stop())

      assert.same(1, #reports_data)
      assert.match("requests=1", reports_data[1])
      assert.match("http_reqs=0", reports_data[1])
      assert.match("https_reqs=1", reports_data[1])
      assert.match("grpc_reqs=0", reports_data[1])
      assert.match("grpcs_reqs=0", reports_data[1])
      assert.match("ws_reqs=0", reports_data[1])
      assert.match("wss_reqs=0", reports_data[1])

      proxy_ssl_client:close()
    end)

    it("reports grpc requests", function()
      local grpc_client = helpers.proxy_client_grpc()
      assert(grpc_client({
        service = "hello.HelloService.SayHello",
        opts = {
          ["-authority"] = "grpc",
        },
      }))

      reports_send_ping()
      local _, reports_data = assert(reports_server:stop())

      assert.same(1, #reports_data)
      assert.match("requests=1", reports_data[1])
      assert.match("http_reqs=0", reports_data[1])
      assert.match("https_reqs=0", reports_data[1])
      assert.match("grpc_reqs=1", reports_data[1])
      assert.match("grpcs_reqs=0", reports_data[1])
      assert.match("ws_reqs=0", reports_data[1])
      assert.match("wss_reqs=0", reports_data[1])
    end)

    it("reports grpcs requests", function()
      local grpcs_client = assert(helpers.proxy_client_grpcs())
      assert(grpcs_client({
        service = "hello.HelloService.SayHello",
        opts = {
          ["-authority"] = "grpcs",
        },
      }))

      reports_send_ping()
      local _, reports_data = assert(reports_server:stop())

      assert.same(1, #reports_data)
      assert.match("requests=1", reports_data[1])
      assert.match("http_reqs=0", reports_data[1])
      assert.match("https_reqs=0", reports_data[1])
      assert.match("grpc_reqs=0", reports_data[1])
      assert.match("grpcs_reqs=1", reports_data[1])
      assert.match("ws_reqs=0", reports_data[1])
      assert.match("wss_reqs=0", reports_data[1])
    end)

    it("reports ws requests", function()
      websocket_send_text_and_get_echo("ws://" .. helpers.get_proxy_ip(false) ..
                                       ":" .. helpers.get_proxy_port(false) .. "/up-ws")

      reports_send_ping()
      local _, reports_data = assert(reports_server:stop())

      assert.same(1, #reports_data)
      assert.match("requests=1", reports_data[1])
      assert.match("http_reqs=0", reports_data[1])
      assert.match("https_reqs=0", reports_data[1])
      assert.match("grpc_reqs=0", reports_data[1])
      assert.match("grpcs_reqs=0", reports_data[1])
      assert.match("ws_reqs=1", reports_data[1])
      assert.match("wss_reqs=0", reports_data[1])
    end)

    it("reports wss requests", function()
      websocket_send_text_and_get_echo("wss://" .. helpers.get_proxy_ip(true) ..
                                       ":" .. helpers.get_proxy_port(true) .. "/up-ws")

      reports_send_ping()
      local _, reports_data = assert(reports_server:stop())

      assert.same(1, #reports_data)
      assert.match("requests=1", reports_data[1])
      assert.match("http_reqs=0", reports_data[1])
      assert.match("https_reqs=0", reports_data[1])
      assert.match("grpc_reqs=0", reports_data[1])
      assert.match("grpcs_reqs=0", reports_data[1])
      assert.match("ws_reqs=0", reports_data[1])
      assert.match("wss_reqs=1", reports_data[1])
    end)
  end)
end
