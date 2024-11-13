local constants = require "kong.constants"
local helpers = require "spec.helpers"
local cjson = require "cjson"


local SAMPLE_YAML_CONFIG = [[
 _format_version: "1.1"
 services:
 - name: my-service
   url: http://127.0.0.1:15555
   routes:
   - name: example-route
     hosts:
     - example.test
]]


local function admin_send(req)
  local client = helpers.admin_client()
  req.method = req.method or "POST"
  req.headers = req.headers or {}
  req.headers["Content-Type"] = req.headers["Content-Type"]
                                or "application/json"
  local res, err = client:send(req)
  if not res then
    return nil, err
  end
  local status, body = res.status, cjson.decode((res:read_body()))
  client:close()
  return status, body
end


for _, strategy in helpers.each_strategy() do

  describe("anonymous reports in Admin API #" .. strategy, function()
    local dns_hostsfile
    local yaml_file
    local reports_server

    lazy_setup(function()
      dns_hostsfile = assert(os.tmpname() .. ".hosts")
      local fd = assert(io.open(dns_hostsfile, "w"))
      assert(fd:write("127.0.0.1 " .. constants.REPORTS.ADDRESS))
      assert(fd:close())

      yaml_file = helpers.make_yaml_file(SAMPLE_YAML_CONFIG)
    end)

    lazy_teardown(function()
      os.remove(dns_hostsfile)
      os.remove(yaml_file)
    end)

    before_each(function()
      reports_server = helpers.tcp_server(constants.REPORTS.STATS_TLS_PORT, {tls=true})

      assert(helpers.get_db_utils(strategy, {}))

      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
        database = strategy,
        dns_hostsfile = dns_hostsfile,
        resolver_hosts_file = dns_hostsfile,
        anonymous_reports = "on",
        declarative_config = yaml_file,
      }, {"routes", "services"}))
    end)

    after_each(function()
      helpers.stop_kong()
    end)

    it("reports plugins added to services via /plugins", function()

      local status, service
      status, service = assert(admin_send({
        method = "POST",
        path = "/services",
        body = {
          protocol = "http",
          host = "example.com",
        },
      }))
      assert.same(201, status)
      assert.string(service.id)

      local plugin
      status, plugin = assert(admin_send({
        method = "POST",
        path = "/plugins",
        body = {
          service = { id = service.id },
          name = "tcp-log",
          config = {
            host = "dummy",
            port = 666,
          },
        },
      }))
      assert.same(201, status)
      assert.string(plugin.id)


      local _, reports_data = assert(reports_server:join())

      assert.match("signal=api", reports_data)
      assert.match("e=s", reports_data)
      assert.match("name=tcp%-log", reports_data)
    end)

    it("reports plugins added to services via /service/:id/plugins", function()

      local status, service
      status, service = assert(admin_send({
        method = "POST",
        path = "/services",
        body = {
          protocol = "http",
          host = "example.com",
        },
      }))
      assert.same(201, status)
      assert.string(service.id)

      local plugin
      status, plugin = assert(admin_send({
        method = "POST",
        path = "/services/" .. service.id .. "/plugins",
        body = {
          name = "tcp-log",
          config = {
            host = "dummy",
            port = 666,
          },
        },
      }))
      assert.same(201, status)
      assert.string(plugin.id)

      local _, reports_data = assert(reports_server:join())

      assert.match("signal=api", reports_data)
      assert.match("e=s", reports_data)
      assert.match("name=tcp%-log", reports_data)
    end)

    it("reports plugins added to routes via /plugins", function()

      local status, service
      status, service = assert(admin_send({
        method = "POST",
        path = "/services",
        body = {
          protocol = "http",
          host = "example.com",
        },
      }))
      assert.same(201, status)
      assert.string(service.id)

      local route
      status, route = assert(admin_send({
        method = "POST",
        path = "/routes",
        body = {
          protocols = { "http" },
          hosts = { "dummy" },
          service = { id = service.id },
        },
      }))
      assert.same(201, status)
      assert.string(route.id)

      local plugin
      status, plugin = assert(admin_send({
        method = "POST",
        path = "/plugins",
        body = {
          route = { id = route.id },
          name = "tcp-log",
          config = {
            host = "dummy",
            port = 666,
          },
        },
      }))
      assert.same(201, status)
      assert.string(plugin.id)

      local _, reports_data = assert(reports_server:join())

      assert.match("signal=api", reports_data)
      assert.match("e=r", reports_data)
      assert.match("name=tcp%-log", reports_data)
    end)

    it("reports plugins added to routes via /routes/:id/plugins", function()

      local status, service
      status, service = assert(admin_send({
        method = "POST",
        path = "/services",
        body = {
          protocol = "http",
          host = "example.com",
        },
      }))
      assert.same(201, status)
      assert.string(service.id)

      local route
      status, route = assert(admin_send({
        method = "POST",
        path = "/routes",
        body = {
          protocols = { "http" },
          hosts = { "dummy" },
          service = { id = service.id },
        },
      }))
      assert.same(201, status)
      assert.string(route.id)

      local plugin
      status, plugin = assert(admin_send({
        method = "POST",
        path = "/routes/" .. route.id .. "/plugins" ,
        body = {
          name = "tcp-log",
          config = {
            host = "dummy",
            port = 666,
          },
        },
      }))
      assert.same(201, status)
      assert.string(plugin.id)

      local _, reports_data = assert(reports_server:join())

      assert.match("signal=api", reports_data)
      assert.match("e=r", reports_data)
      assert.match("name=tcp%-log", reports_data)
    end)

    if strategy == "off" then
      it("reports declarative reconfigure via /config", function()

        local status, config = assert(admin_send({
          path    = "/config",
          body    = {
            config = SAMPLE_YAML_CONFIG,
          },
          headers = {
            ["Content-Type"] = "multipart/form-data",
          }
        }))
        assert.same(201, status)
        assert.table(config)

        local _, reports_data = assert(reports_server:join())

        assert.match("signal=dbless-reconfigure", reports_data, nil, true)
        -- it will be updated on-the-fly
        -- but the version should still be 1.1
        assert.match("decl_fmt_version=1.1", reports_data, nil, true)
      end)
    end

  end)
end
