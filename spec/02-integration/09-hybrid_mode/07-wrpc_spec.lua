local match = require "luassert.match"
local ws_client, ws_server, wrpc, wrpc_proto
local wait_for_log
local ngx_log = ngx.log

local timeout = 200 -- for perf test
local max_payload_len = 1024 * 1024 * 200

local default_ws_opt = {
  timeout = timeout,
  max_payload_len = max_payload_len,
}

local echo_service = "TestService.Echo"


local function contain(state, arguments)
  local expected = arguments[1]
  return function(value)
    return type(value) == "string" and value:find(expected) and true
  end
end

assert:register("matcher", "contain", contain)

local function new_server(ws_peer)
  local proto = wrpc_proto.new()
  proto:addpath("spec/fixtures/wrpc")
  proto:import("test")
  proto:set_handler("TestService.Echo", function(_, msg)
    if msg.message == "log" then
      ngx.log(ngx.NOTICE, "log test!")
    end
    return msg
  end)
  local peer = assert(wrpc.new_peer(ws_peer, proto, timeout))
  peer:spawn_threads()
  return peer
end

local function new_client(ws_peer)
  local proto = wrpc_proto.new()
  proto:addpath("spec/fixtures/wrpc")
  proto:import("test")
  local peer = assert(wrpc.new_peer(ws_peer, proto, timeout))
  peer:spawn_threads()
  return peer
end

local to_close = {}

local function new_pair(ws_opt)
  local client_ws = ws_client:new(ws_opt or default_ws_opt)
  local server_ws = ws_server:new(ws_opt or default_ws_opt)
  server_ws.peer = client_ws
  client_ws.peer = server_ws

  local client, server = new_client(client_ws), new_server(server_ws)

  table.insert(to_close, client)
  table.insert(to_close, server)

  return client, server
end

insulate("wRPC protocol implementation", function()
  lazy_setup(function ()
    -- mock
    -- we don't use mock() or spy() because it fails to mock somehow
    local inspect = require "inspect"
    local log_spy = spy.new(function () end)
    ngx.log = function(level, ...) -- luacheck: ignore
      return log_spy(level, inspect{...}) -- to make sure msg
    end
    -- require here. otherwise mock will fail
    local wait_until = require "spec.helpers".wait_until
    function wait_for_log(...)
      local logs = {...}
      wait_until(function ()
        for _, log in ipairs(logs) do
          if not pcall(assert.spy(log_spy).was_called_with, match._, match.contain(log)) then
            return
          end
        end
        return true
      end, 5)
    end

    package.loaded["kong.tools.wrpc"] = nil
    package.loaded["kong.tools.wrpc.message"] = nil
    require "kong.tools.wrpc"
    require "kong.tools.wrpc.message"

    -- if we require at outer scope, the mock would be too late
    ws_client = require("spec.fixtures.mocks.lua-resty-websocket.resty.websocket.peer")
    ws_server = require("spec.fixtures.mocks.lua-resty-websocket.resty.websocket.peer")

    wrpc = require("kong.tools.wrpc")
    wrpc_proto = require("kong.tools.wrpc.proto")
  end)

  lazy_teardown(function ()
    ngx.log = ngx_log -- luacheck: ignore
  end)

  describe("simple echo tests", function()

    after_each(function ()
      for i = 1, #to_close do
        to_close[i]:close()
        to_close[i] = nil
      end
    end)

    it("multiple client, multiple call waiting", function ()
      local client_n = 30
      local message_n = 1000

      local expecting = {}

      local clients = {}
      for i = 1, client_n do
        clients[i] = new_pair()
      end

      for i = 1, message_n do
        local client = math.random(1, client_n)
        local message = client .. ":" .. math.random(1, 160)
        local future = clients[client]:call(echo_service, { message = message, })
        expecting[i] = {future = future, message = message, }
      end

      for i = 1, message_n do
        local message = assert(expecting[i].future:wait())
        assert(message.message == expecting[i].message)
      end

    end)

    it("API test", function ()
      local client = new_pair()
      local param = { message = "log", }

      assert.same(param, client:call_async(echo_service, param))
      wait_for_log("log test!")

      assert(client:call_no_return(echo_service, param))
      wait_for_log("log test!")

      
      local rpc, payloads = assert(client.service:encode_args(echo_service, param))
      local future = assert(client:send_encoded_call(rpc, payloads))
      assert.same(param, future:wait())
      wait_for_log("log test!")
    end)

    it("errors", function ()
      local future = require "kong.tools.wrpc.future"
      local client = new_pair()
      local param = { message = "log", }
      local rpc, payloads = assert(client.service:encode_args(echo_service, param))

      local response_future = future.new(client, client.timeout)
      client:send_payload({
        mtype = "MESSAGE_TYPE_RPC",
        svc_id = rpc.svc_id,
        rpc_id = rpc.rpc_id + 1,
        payload_encoding = "ENCODING_PROTO3",
        payloads = payloads,
      })
      assert.same({
        nil, "Invalid service (or rpc)"
      },{response_future:wait()})

      response_future = future.new(client, client.timeout)
      client:send_payload({
        mtype = "MESSAGE_TYPE_RPC",
        svc_id = rpc.svc_id + 1,
        rpc_id = rpc.rpc_id,
        payload_encoding = "ENCODING_PROTO3",
        payloads = payloads,
      })
      assert.same({
        nil, "Invalid service (or rpc)"
      },{response_future:wait()})

      local client2 = new_pair({
        max_payload_len = 25,
      })

      assert(
        {
          nil, "payload too large"
        },
        client2:send_payload({
          mtype = "MESSAGE_TYPE_RPC",
          svc_id = rpc.svc_id,
          rpc_id = rpc.rpc_id,
          payload_encoding = "ENCODING_PROTO3",
          payloads = string.rep("t", 26),
        })
      )

      local other_types = {
        "MESSAGE_TYPE_UNSPECIFIED",
        "MESSAGE_TYPE_STREAM_BEGIN",
        "MESSAGE_TYPE_STREAM_MESSAGE",
        "MESSAGE_TYPE_STREAM_END",
      }

      for _, typ in ipairs(other_types) do
        response_future = future.new(client, client.timeout)
        client:send_payload({
          mtype = typ,
          svc_id = rpc.svc_id,
          rpc_id = rpc.rpc_id,
          payload_encoding = "ENCODING_PROTO3",
          payloads = payloads,
        })

        assert.same({
          nil, "Unsupported message type"
        },{response_future:wait()})
      end

      -- those will mess up seq so must be put at the last
      client:send_payload({
        mtype = "MESSAGE_TYPE_ERROR",
        svc_id = rpc.svc_id,
        rpc_id = rpc.rpc_id,
        payload_encoding = "ENCODING_PROTO3",
        payloads = payloads,
      })
      wait_for_log("malformed wRPC message")
      
      client:send_payload({
        ack = 11,
        mtype = "MESSAGE_TYPE_ERROR",
        svc_id = rpc.svc_id,
        rpc_id = rpc.rpc_id,
        payload_encoding = "ENCODING_PROTO3",
        payloads = payloads,
      })
      wait_for_log("receiving error message for a call expired or not initiated by this peer.")
      
      client:send_payload({
        ack = 11,
        mtype = "MESSAGE_TYPE_ERROR",
        svc_id = rpc.svc_id,
        rpc_id = rpc.rpc_id + 1,
        payload_encoding = "ENCODING_PROTO3",
        payloads = payloads,
      })
      wait_for_log("receiving error message for a call expired or not initiated by this peer.", "receiving error message for unkonwn RPC")
    end)
    
    it("#perf", function ()
      local semaphore = require "ngx.semaphore"
      local smph = semaphore.new()

      local client_n = 8
      local message_n = 160

      local m = 16 -- ?m
      local message = string.rep("testbyte\x00\xff\xab\xcd\xef\xc0\xff\xee", 1024*64*m)

      local done = 0
      local t = ngx.now()
      local time
      local function counter(premature, future)
        assert(future:wait(200))
        done = done + 1
        if done == message_n then
          local t2 = ngx.now()
          time = t2 - t
          smph:post()
        end
      end

      local clients = {}
      for i = 1, client_n do
        clients[i] = new_pair()
      end

      for i = 0, message_n - 1 do
        local client = (i % client_n) + 1
        local future = assert(clients[client]:call(echo_service, { message = message, }))
        ngx.timer.at(0, counter, future)
      end

      -- in my env(i7-1165G7) it takes less than 3.7s
      assert(smph:wait(10) and time < 10, "wrpc spent too much time")
    end)
  
  end)
end)
