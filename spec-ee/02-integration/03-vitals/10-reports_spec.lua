-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local constants = require "kong.constants"
local helpers = require "spec.helpers"
local pl_file = require "pl.file"


for _, strategy in helpers.each_strategy() do
    describe("anonymous reports in Vitals when it's off #" .. strategy, function()
      local dns_hostsfile
      local reports_server

      local reports_send_ping = function(opts)
        ngx.sleep(0.01) -- hand over the CPU so other threads can do work (processing the sent data)
        local admin_client = helpers.admin_client()
        opts = opts or {}
        local port = opts.port or nil
        local res = admin_client:post("/reports/send-ping" .. (port and "?port=" .. port or ""))
        assert.response(res).has_status(200)
        admin_client:close()
      end


      lazy_setup(function()
        dns_hostsfile = assert(os.tmpname()  .. ".hosts")
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
                           hosts = { "http-service.test" } })

        bp.routes:insert({ service = http_srv,
                           protocols = { "https" },
                           hosts = { "https-service.test" } })


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
          vitals = false,
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

      after_each(function()
        helpers.stop_kong()
      end)

      it("reports vitals backend strategy", function()
        local proxy_client = assert(helpers.proxy_client())
        local res = proxy_client:get("/", {
          headers = { host  = "http-service.test" }
        })
        assert.response(res).has_status(200)

        reports_send_ping({port=constants.REPORTS.STATS_TLS_PORT})

        local _, reports_data = assert(reports_server:join())
        assert.is_nil(string.find(reports_data, "vitals_backend="))

        proxy_client:close()
      end)
    end)
  for _, vitals_strategy in pairs({"database", "prometheus", "influxdb"}) do

  -- Might need to be marked as flaky because it may require an arbitrary high port?
    describe("anonymous reports in Vitals backed by database #" .. strategy, function()
      local dns_hostsfile
      local reports_server
      local license_env

      local reports_send_ping = function()
        ngx.sleep(0.01) -- hand over the CPU so other threads can do work (processing the sent data)
        local admin_client = helpers.admin_client()
        local res = admin_client:post("/reports/send-ping")
        assert.response(res).has_status(200)
        admin_client:close()
      end


      lazy_setup(function()
        license_env = os.getenv("KONG_LICENSE_DATA")
        helpers.setenv("KONG_LICENSE_DATA", pl_file.read("spec-ee/fixtures/mock_license.json"))

        dns_hostsfile = assert(os.tmpname()  .. ".hosts")
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
                           hosts = { "http-service.test" } })

        bp.routes:insert({ service = http_srv,
                           protocols = { "https" },
                           hosts = { "https-service.test" } })


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
          vitals = true,
          portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
          vitals_strategy = vitals_strategy,
          vitals_tsdb_address = "a-valid-address:9000",
          vitals_statsd_address = "another-valid-address:9000",
          plugins = "reports-api",
          stream_listen = helpers.get_proxy_ip(false) .. ":19000," ..
                          helpers.get_proxy_ip(false) .. ":19001," ..
                          helpers.get_proxy_ip(true)  .. ":19443 ssl",

        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong()

        os.remove(dns_hostsfile)

        if type(license_env) == "string" then
          helpers.setenv("KONG_LICENSE_DATA", license_env)
        end
      end)

      before_each(function()
        reports_server = helpers.tcp_server(constants.REPORTS.STATS_TLS_PORT, {tls=true})
      end)

      after_each(function()
        helpers.stop_kong()
      end)

      it("reports vitals backend strategy", function()
        local proxy_client = assert(helpers.proxy_client())
        local res = proxy_client:get("/", {
          headers = { host  = "http-service.test" }
        })
        assert.response(res).has_status(200)

        reports_send_ping({port=constants.REPORTS.STATS_TLS_PORT})

        local _, reports_data = assert(reports_server:join())
        assert.match("vitals_backend=" .. vitals_strategy, reports_data)

        proxy_client:close()
      end)
    end)
  end
end
