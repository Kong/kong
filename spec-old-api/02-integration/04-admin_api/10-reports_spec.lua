local constants = require "kong.constants"
local helpers = require "spec.helpers"
local cjson = require "cjson"
local dao_helpers = require "spec-old-api.02-integration.03-dao.helpers"

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
  ngx.sleep(0.1)
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

dao_helpers.for_each_dao(function(kong_config)
  local strategy = kong_config.database

  -- Marked as flaky because they require an arbitrary high port
  describe("#flaky anonymous reports in Admin API #" .. strategy, function()
    local dns_hostsfile
    local reports_server
    local db
    local dao

    setup(function()
      local _
      _, db, dao = helpers.get_db_utils(strategy)
      dns_hostsfile = assert(os.tmpname())
      local fd = assert(io.open(dns_hostsfile, "w"))
      assert(fd:write("127.0.0.1 " .. constants.REPORTS.ADDRESS))
      assert(fd:close())
    end)

    teardown(function()
      os.remove(dns_hostsfile)
    end)

    before_each(function()
      reports_server = mock_reports_server()

      assert(db:truncate())
      dao:truncate_tables()
      assert(dao:run_migrations())

      assert(helpers.start_kong({
        database = strategy,
        dns_hostsfile = dns_hostsfile,
        anonymous_reports = "on",
      }))
    end)

    after_each(function()
      helpers.stop_kong()
    end)

    it("reports plugins added to apis via /plugins", function()

      local status, api
      status, api = assert(admin_send({
        method = "POST",
        path = "/apis",
        body = {
          name = "dummy",
          hosts = "dummy",
          upstream_url = "http://dummy"
        },
      }))
      assert.same(201, status)
      assert.string(api.id)

      local plugin
      status, plugin = assert(admin_send({
        method = "POST",
        path = "/plugins",
        body = {
          api_id = api.id,
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
      assert.match("e=a", reports_data[1])
      assert.match("name=tcp%-log", reports_data[1])
    end)

    it("reports plugins added to apis via /apis/:api_id:/plugins", function()

      local status, api
      status, api = assert(admin_send({
        method = "POST",
        path = "/apis",
        body = {
          name = "dummy",
          hosts = "dummy",
          upstream_url = "http://dummy"
        },
      }))
      assert.same(201, status)
      assert.string(api.id)

      local plugin
      status, plugin = assert(admin_send({
        method = "POST",
        path = "/apis/" .. api.id .. "/plugins",
        body = {
          api_id = api.id,
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
      assert.match("e=a", reports_data[1])
      assert.match("name=tcp%-log", reports_data[1])
    end)

  end)

end)
