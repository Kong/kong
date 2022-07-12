local helpers = require "spec.helpers"

local ws_client = require("resty.websocket.client")
local wrpc = require("kong.tools.wrpc")
local wrpc_proto = require("kong.tools.wrpc.proto")

local pl_file = require("pl.file")
local ssl = require("ngx.ssl")

local timeout = 10
local max_payload_len = 4194304

local function connect_wrpc_peer(address, cert, cert_key, client_proto)
  local c, err = ws_client:new {
    timeout = timeout,
    max_payload_len = 4194304,
  }

  if not c then return nil, err end

  local opts = {
    ssl_verify = false,
    client_cert = cert,
    client_priv_key = cert_key,
    protocols = "wrpc.konghq.com",
  }

  local ok, err = c:connect(address, opts)
  if not ok then
    return nil, err
  end

  local proto = wrpc_proto.new()
  proto:addpath("spec/fixtures/wrpc")
  proto:import(client_proto)
  local peer = wrpc.new_peer(c, proto, timeout)
  peer:spawn_threads()

  return peer
end

local function expand_template(str, var)
  return ngx.re.gsub(str, [[\${{(\w+)}}]], function(m)
    return var[m[1]]
  end)
end

local template =
[[
  server {
    listen ${{PORT}} ssl;    
    ssl_verify_client   on;
    ssl_client_certificate ../${{CERT_CA}};
    ssl_verify_depth     4;
    ssl_certificate     ../${{CERT}};
    ssl_certificate_key ../${{CERT_KEY}};
    ssl_session_cache   shared:ClusterSSL:10m;

    location = / {
      content_by_lua_block {
        ${{CODE}}
      }
    }
  }
]]

local code_tmp = expand_template([[
  local wrpc = require("kong.tools.wrpc")
  local proto = require("kong.tools.wrpc.proto").new()
  proto:addpath(ngx.config.prefix() .. "/../spec/fixtures/wrpc")
  proto:import("${{PROTO}}")

  
  local WS_OPTS = {
    timeout = ${{TIMEOUT}},
    max_payload_len = ${{MAX_PAYLOAD_LEN}},
  }

  local ws_server = require("resty.websocket.server")
  local wb, err = ws_server:new(WS_OPTS)

  local w_peer = wrpc.new_peer(wb, proto)
  -- add more proto if you want in "RPC_CODE"
  ${{CODE}}
  w_peer:spawn_threads()
  w_peer:wait_threads()
  w_peer:close()
  return ngx.exit(ngx.HTTP_CLOSE)
]], {
  PROTO = "${{PROTO}}", CODE = "${{CODE}}",
  TIMEOUT = timeout, MAX_PAYLOAD_LEN = max_payload_len,
})

local port = 25535


local client_cert = "spec/fixtures/kong_clustering_client.crt"
local client_cert_key = "spec/fixtures/kong_clustering_client.key"

local cert_key = "spec/fixtures/kong_clustering.key"
local cert = "spec/fixtures/kong_clustering.crt"
local cert_ca = "spec/fixtures/kong_clustering_ca.crt"

local cert_f = assert(pl_file.read(client_cert))
local cert_b = assert(ssl.parse_pem_cert(cert_f))
local key_f = assert(pl_file.read(client_cert_key))
local cert_key_b = assert(ssl.parse_pem_priv_key(key_f))

local function start_kong_with_code(code)
  local fixtures = { http_mock = { wrpc =
  expand_template(template, {
    CODE = code, PORT = port,
    CERT = cert, CERT_KEY = cert_key, CERT_CA = cert_ca,
  }),
  }, }

  return helpers.start_kong({
    nginx_conf = "spec/fixtures/custom_nginx.template",
    database = "off",
    nginx_worker_processes = 1, -- extreme setup
  }, nil, nil, fixtures)
end

local function start_wrpc_server_and_client(proto, code)
  assert(start_kong_with_code(expand_template(code_tmp, {
    PROTO = proto, CODE = code or "",
  })))

  assert.logfile().has.no.line("[error]", true)
  return function()
    return assert(connect_wrpc_peer("wss://localhost:" .. port .. "/", cert_b, cert_key_b, proto))
  end
end

local function stop_wrpc_server()
  helpers.stop_kong()
end

describe("wRPC protocol implementation", function()
  local client_maker
  describe("simple echo tests", function()
    lazy_setup(function()
      client_maker = start_wrpc_server_and_client("test", [[
        proto:set_handler("TestService.Echo", function(peer, msg)
          return msg
        end)
      ]])
    end)
    lazy_teardown(function()
      stop_wrpc_server()
    end)

    -- it("1 time of echo", function()
    --   local echo_back = assert(client_maker():call_async("TestService.Echo", { message = "1", }))
    --   assert.same({
    --     message = "1"
    --   }, echo_back)
    -- end)

    it("multiple client, multiple call waiting", function ()
      local client_n = 30
      local message_n = 1000

      local expecting = {}

      local clients = {}
      for i = 1, client_n do
        clients[i] = client_maker()
      end

      for i = 1, message_n do
        local client = math.random(1, client_n)
        local message = client .. ":" .. math.random(1, 160)
        local future = clients[client]:call("TestService.Echo", { message = message, })
        expecting[i] = {future = future, message = message, }
      end

      for i = 1, message_n do
        local message = assert(expecting[i].future:wait())
        assert(message.message == expecting[i].message)
      end

    end)
  end)
end)
