local helpers = require "spec.helpers"
local utils = require "pl.utils"
local http = require "resty.http"
local constants = require "kong.constants"


local strip = require("kong.tools.string").strip


local function count_server_blocks(filename)
  local file = assert(utils.readfile(filename))
  local _, count = file:gsub("[%\n%s]+server%s{%s*\n","")
  return count
end


local function get_listeners(filename)
  local file = assert(utils.readfile(filename))
  local result = {}
  for block in file:gmatch("[%\n%s]+server%s+(%b{})") do
    local server_name = block:match("[%\n%s]server_name%s(.-);")
    server_name = server_name and strip(server_name) or "stream"
    local server = result[server_name] or {}
    result[server_name] = server
    for listen in block:gmatch("[%\n%s]listen%s(.-);") do
      listen = strip(listen)
      table.insert(server, listen)
      server[listen] = #server
    end
  end
  return result
end


describe("Proxy interface listeners", function()
  before_each(function()
    helpers.get_db_utils(nil, {})
  end)

  after_each(function()
    helpers.stop_kong()
  end)

  it("disabled", function()
    assert(helpers.start_kong({
      proxy_listen = "off",
      admin_listen = "0.0.0.0:9001",
      admin_gui_listen = "off",
    }))
    assert.equals(2, count_server_blocks(helpers.test_conf.nginx_kong_conf))
    assert.is_nil(get_listeners(helpers.test_conf.nginx_kong_conf).kong)
  end)

  it("multiple", function()
    assert(helpers.start_kong({
      proxy_listen = "127.0.0.1:9001, 127.0.0.1:9002",
      admin_listen = "0.0.0.0:9000",
      admin_gui_listen = "off",
    }))

    assert.equals(3, count_server_blocks(helpers.test_conf.nginx_kong_conf))
    assert.same({
      ["127.0.0.1:9001"] = 1,
      ["127.0.0.1:9002"] = 2,
      [1] = "127.0.0.1:9001",
      [2] = "127.0.0.1:9002",
    }, get_listeners(helpers.test_conf.nginx_kong_conf).kong)

    for i = 9001, 9002 do
      local client = assert(http.new())
      assert(client:connect("127.0.0.1", i))

      local res = assert(client:request {
        method = "GET",
        path = "/"
      })
      res:read_body()
      client:close()
      assert.equals(404, res.status)
    end
  end)
end)

describe("#stream proxy interface listeners", function()
  before_each(function()
    helpers.get_db_utils()
  end)

  after_each(function()
    helpers.stop_kong()
  end)

  it("disabled", function()
    assert(helpers.start_kong({
      stream_listen = "off",
    }))
    assert.equals(1, count_server_blocks(helpers.test_conf.nginx_kong_stream_conf))
    assert.is_nil(get_listeners(helpers.test_conf.nginx_kong_stream_conf).kong)
  end)

  it("multiple", function()
    assert(helpers.start_kong({
      stream_listen = "127.0.0.1:9011, 127.0.0.1:9012",
    }))

    local stream_events_sock_path = "unix:" .. helpers.test_conf.socket_path .. "/" .. constants.SOCKETS.STREAM_WORKER_EVENTS

    if helpers.test_conf.database == "off" then
      local stream_config_sock_path = "unix:" .. helpers.test_conf.socket_path .. "/" .. constants.SOCKETS.STREAM_CONFIG

      assert.equals(3, count_server_blocks(helpers.test_conf.nginx_kong_stream_conf))
      assert.same({
        ["127.0.0.1:9011"] = 1,
        ["127.0.0.1:9012"] = 2,
        [stream_config_sock_path] = 3,
        [stream_events_sock_path] = 4,
        [1] = "127.0.0.1:9011",
        [2] = "127.0.0.1:9012",
        [3] = stream_config_sock_path,
        [4] = stream_events_sock_path,
      }, get_listeners(helpers.test_conf.nginx_kong_stream_conf).stream)

    else
      assert.equals(2, count_server_blocks(helpers.test_conf.nginx_kong_stream_conf))
      assert.same({
        ["127.0.0.1:9011"] = 1,
        ["127.0.0.1:9012"] = 2,
        [stream_events_sock_path] = 3,
        [1] = "127.0.0.1:9011",
        [2] = "127.0.0.1:9012",
        [3] = stream_events_sock_path,
      }, get_listeners(helpers.test_conf.nginx_kong_stream_conf).stream)
    end

    for i = 9011, 9012 do
      local sock = ngx.socket.tcp()
      assert(sock:connect("127.0.0.1", i))
      assert(sock:send("hi"))
      sock:close()
    end
  end)
end)


local function reload_router(flavor)
  helpers = require("spec.internal.module").reload_helpers(flavor)
end


-- TODO: remove it when we confirm it is not needed
local function gen_route(flavor, r)
  return r
end


for _, flavor in ipairs({ "traditional", "traditional_compatible", "expressions" }) do
for _, strategy in helpers.each_strategy() do
  if strategy ~= "off" then
    describe("[stream" .. ", flavor = " .. flavor .. "]", function()
      reload_router(flavor)

      local MESSAGE = "echo, ping, pong. echo, ping, pong. echo, ping, pong.\n"
      lazy_setup(function()
        local bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "plugins",
        })

        local service = assert(bp.services:insert {
          host     = helpers.mock_upstream_host,
          port     = helpers.mock_upstream_stream_port,
          protocol = "tcp",
        })

        assert(bp.routes:insert(gen_route(flavor, {
          destinations = {
            { port = 19000 },
          },
          protocols = {
            "tcp",
          },
          service = service,
        })))

        assert(bp.routes:insert(gen_route(flavor, {
          protocols = { "tcp" },
          service   = service,
          destinations = {
            { ip = "0.0.0.0", port = 19004 },
            { ip = "0.0.0.0", port = 19005 },
            { ip = "0.0.0.0", port = 19006 },
            { ip = "0.0.0.0", port = 19007 },
            { ip = "0.0.0.0" },
            { port = 19004 },
          }
        })))

        assert(bp.routes:insert(gen_route(flavor, {
          protocols = { "tcp" },
          service   = service,
          destinations = {
            { ip = "0.0.0.0", port = 19004 },
            { ip = "0.0.0.0", port = 19005 },
            { ip = "0.0.0.0", port = 19006 },
            { ip = "0.0.0.0", port = 19007 },
            { ip = "0.0.0.0" },
            { port = 19004 },
          }
        })))

        assert(bp.routes:insert(gen_route(flavor, {
          protocols = { "tcp" },
          service   = service,
          destinations = {
            { ip = "0.0.0.0", port = 19004 },
            { ip = "0.0.0.0", port = 19005 },
            { ip = "0.0.0.0", port = 19006 },
            { ip = "0.0.0.0", port = 19007 },
            { ip = "0.0.0.0" },
            { port = 19004 },
          }
        })))

        assert(bp.routes:insert(gen_route(flavor, {
          protocols = { "tcp" },
          service   = service,
          destinations = {
            { ip = "0.0.0.0", port = 19004 },
            { ip = "0.0.0.0", port = 19005 },
            { ip = "0.0.0.0", port = 19006 },
            { ip = "0.0.0.0", port = 19007 },
            { ip = "0.0.0.0" },
            { port = 19004 },
          }
        })))

        assert(bp.routes:insert(gen_route(flavor, {
          protocols = { "tcp" },
          service   = service,
          destinations = {
            { ip = "0.0.0.0", port = 19004 },
            { ip = "0.0.0.0", port = 19005 },
            { ip = "0.0.0.0", port = 19006 },
            { ip = "0.0.0.0", port = 19007 },
            { ip = "0.0.0.0" },
            { port = 19004 },
          }
        })))

        assert(helpers.start_kong({
          router_flavor = flavor,
          database      = strategy,
          stream_listen = helpers.get_proxy_ip(false) .. ":19000, " ..
                          helpers.get_proxy_ip(false) .. ":18000, " ..
                          helpers.get_proxy_ip(false) .. ":17000",
          port_maps     = "19000:18000",
          plugins       = "bundled,ctx-tests",
          nginx_conf    = "spec/fixtures/custom_nginx.template",
          proxy_listen  = "off",
          admin_listen  = "off",
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("routes by destination port without port map", function()
        local tcp_client = ngx.socket.tcp()
        assert(tcp_client:connect(helpers.get_proxy_ip(false), 19000))
        assert(tcp_client:send(MESSAGE))
        local body = assert(tcp_client:receive("*a"))
        assert.equal(MESSAGE, body)
        assert(tcp_client:close())
      end)

      it("uses port maps configuration to route by destination port", function()
        local tcp_client = ngx.socket.tcp()
        assert(tcp_client:connect(helpers.get_proxy_ip(false), 18000))
        assert(tcp_client:send(MESSAGE))
        local body = assert(tcp_client:receive("*a"))
        assert.equal(MESSAGE, body)
        assert(tcp_client:close())
      end)

      it("fails to route when no port map is specified and route is not found", function()
        local tcp_client = ngx.socket.tcp()
        assert(tcp_client:connect(helpers.get_proxy_ip(false), 17000))
        assert(tcp_client:send(MESSAGE))
        local body, err = tcp_client:receive("*a")
        if not err then
          assert.equal("", body)
        else
          assert.equal("connection reset by peer", err)
        end
        assert(tcp_client:close())
      end)

      it("destinations has more than 3 items", function()
        assert.logfile().has.no.line("invalid order function for sorting", true)
      end)
    end)
  end
end
end   -- for flavor
