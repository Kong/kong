local constants = require "kong.constants"
local helpers = require "spec.helpers"
local cjson = require "cjson"


local localhost = "127.0.0.1"


local function mock_reports_server()
  local threads = require "llthreads2.ex"
  local server_port = constants.REPORTS.STATS_PORT

  local thread = threads.new({
    function(port, localhost)
      local socket = require "socket"

      local server = assert(socket.udp())
      server:settimeout(1)
      server:setoption("reuseaddr", true)
      server:setsockname(localhost, port)
      local data = {}
      local started = false
      while true do
        local packet, recvip, recvport = server:receivefrom()
        if packet then
          if packet == "\\START" then
            if not started then
              started = true
              server:sendto("\\OK", recvip, recvport)
            end
          elseif packet == "\\STOP" then
            break
          else
            table.insert(data, packet)
          end
        end
      end
      server:close()
      return data
    end
  }, server_port, localhost)
  thread:start()

  local handshake_skt = assert(ngx.socket.udp())
  handshake_skt:setpeername(localhost, server_port)
  handshake_skt:settimeout(0.1)

  -- not necessary for correctness because we do the handshake,
  -- but avoids harmless "connection error" messages in the wait loop
  -- in case the client is ready before the server below.
  ngx.sleep(0.01)

  while true do
    handshake_skt:send("\\START")
    local ok = handshake_skt:receive()
    if ok == "\\OK" then
      break
    end
  end
  handshake_skt:close()

  return {
    stop = function()
      local skt = assert(ngx.socket.udp())
      skt:setpeername(localhost, server_port)
      skt:send("\\STOP")
      skt:close()

      return thread:join()
    end
  }
end


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

  -- Marked as flaky because they require an arbitrary high port
  describe("#flaky anonymous reports in Admin API #" .. strategy, function()
    local dns_hostsfile
    local reports_server

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
      reports_server = mock_reports_server()

      assert(helpers.get_db_utils(strategy, {}))

      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
        database = strategy,
        dns_hostsfile = dns_hostsfile,
        anonymous_reports = "on",
      }))
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

      local _, reports_data = assert(reports_server:stop())

      assert.same(1, #reports_data)
      assert.match("signal=api", reports_data[1])
      assert.match("e=s", reports_data[1])
      assert.match("name=tcp%-log", reports_data[1])
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

      local _, reports_data = assert(reports_server:stop())

      assert.same(1, #reports_data)
      assert.match("signal=api", reports_data[1])
      assert.match("e=s", reports_data[1])
      assert.match("name=tcp%-log", reports_data[1])
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

      local _, reports_data = assert(reports_server:stop())

      assert.same(1, #reports_data)
      assert.match("signal=api", reports_data[1])
      assert.match("e=r", reports_data[1])
      assert.match("name=tcp%-log", reports_data[1])
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

      local _, reports_data = assert(reports_server:stop())

      assert.same(1, #reports_data)
      assert.match("signal=api", reports_data[1])
      assert.match("e=r", reports_data[1])
      assert.match("name=tcp%-log", reports_data[1])
    end)

  end)
end
