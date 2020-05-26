local helpers = require "spec.helpers"
local constants = require "kong.constants"
local cjson = require "cjson"


for _, strategy in helpers.each_strategy() do
  local admin_client
  local dns_hostsfile
  local reports_server

  describe("anonymous reports for go plugins #" .. strategy, function()
    local reports_send_ping = function(port)
      ngx.sleep(0.01) -- hand over the CPU so other threads can do work (processing the sent data)
      local admin_client = helpers.admin_client()
      local res = admin_client:post("/reports/send-ping" .. (port and "?port=" .. port or ""))
      assert.response(res).has_status(200)
      admin_client:close()
    end

    local OLD_STATS_PORT = constants.REPORTS.STATS_PORT
    local NEW_STATS_PORT

    lazy_setup(function()
      NEW_STATS_PORT = OLD_STATS_PORT + math.random(1, 50)
      constants.REPORTS.STATS_PORT = NEW_STATS_PORT

      dns_hostsfile = assert(os.tmpname())
      local fd = assert(io.open(dns_hostsfile, "w"))
      assert(fd:write("127.0.0.1 " .. constants.REPORTS.ADDRESS))
      assert(fd:close())

      local bp = assert(helpers.get_db_utils(strategy, {
        "services",
        "routes",
        "plugins",
      }, { "reports-api" }))

      local http_srv = assert(bp.services:insert {
        name = "mock-service",
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
      })

      bp.routes:insert({ service = http_srv,
                         protocols = { "http" },
                         hosts = { "http-service.test" }})

      bp.plugins:insert({
        name = "reports-api",
        config = {}
      })

      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
        database = strategy,
        dns_hostsfile = dns_hostsfile,
        plugins = "bundled,reports-api,go-hello",
        go_plugins_dir = helpers.go_plugin_path,
        anonymous_reports = true,
      }))

      admin_client = helpers.admin_client()

      local res = admin_client:post("/plugins", {
        headers = {
          ["Content-Type"] = "application/json"
        },
        body = {
          name = "go-hello",
          config = {
            message = "Kong!"
          }
        }
      })
      assert.res_status(201, res)
    end)

    lazy_teardown(function()
      os.remove(dns_hostsfile)
      constants.REPORTS.STATS_PORT = OLD_STATS_PORT

      helpers.stop_kong()
    end)

    before_each(function()
      reports_server = helpers.mock_reports_server()
    end)

    after_each(function()
      reports_server:stop() -- stop the reports server if it was not already stopped
    end)

    it("logs number of enabled go plugins", function()
      reports_send_ping(NEW_STATS_PORT)

      local _, reports_data = assert(reports_server:stop())
      reports_data = cjson.encode(reports_data)

      assert.match("go_plugins_cnt=1", reports_data)
    end)

    it("logs number of requests triggering a go plugin", function()
      local proxy_client = assert(helpers.proxy_client())
      local res = proxy_client:get("/", {
        headers = { host  = "http-service.test" }
      })
      assert.res_status(200, res)

      reports_send_ping(NEW_STATS_PORT)

      local _, reports_data = assert(reports_server:stop())
      reports_data = cjson.encode(reports_data)

      assert.match("go_plugin_reqs=1", reports_data)
      assert.match("go_plugin_reqs=1", reports_data)
      proxy_client:close()
    end)

    it("logs the go version in use", function()
      local proxy_client = assert(helpers.proxy_client())
      local res = proxy_client:get("/", {
        headers = { host  = "http-service.test" }
      })
      assert.res_status(200, res)

      reports_send_ping(NEW_STATS_PORT)

      local _, reports_data = assert(reports_server:stop())
      reports_data = cjson.encode(reports_data)

      assert.match("go_version=%d+.%d+.%d*", reports_data)
      proxy_client:close()
    end)
  end)
end
