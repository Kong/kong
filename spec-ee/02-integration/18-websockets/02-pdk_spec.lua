-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local ee_helpers = require "spec-ee.helpers"
local helpers    = require "spec.helpers"
local cjson      = require "cjson"
local pl_path    = require "pl.path"
local pl_file    = require "pl.file"
local ws         = require "spec-ee.fixtures.websocket"
local WS         = require "spec-ee.fixtures.websocket.action"
local RPC        = require "spec-ee.fixtures.websocket.rpc"
local ws_session = require "spec-ee.fixtures.websocket.session"

local ws_proxy_client = ee_helpers.ws_proxy_client
local SERVER_ERROR = ws.const.status.SERVER_ERROR
local TOO_BIG = ws.const.status.MESSAGE_TOO_BIG

local rep = string.rep


local function handshake(opts)
  local client, err = ws_proxy_client(opts)
  assert.is_nil(err)

  client.response:read_body()
  client:close()

  return client.response
end


local function await_file(fname)
  helpers.wait_until(function()
    return pl_path.exists(fname) and pl_path.getsize(fname) > 0
  end, 5, 0.1)
end

local function assert_file_contents(fname, str)
  await_file(fname)
  local content = pl_file.read(fname)
  assert.equals(str, content)
end

local PEERS = {
  client = "upstream",
  upstream = "client",
}


for _, strategy in helpers.each_strategy() do
describe("WebSocket PDK #" .. strategy, function()
  setup(function()
    local bp = helpers.get_db_utils(
      strategy,
      {
        "routes",
        "services",
        "plugins",
      },
      { "pre-function", "post-function" }
    )


    local service = bp.services:insert {
      name = "ws",
      protocol = "ws",
      port = ws.const.ports.ws,
    }

    bp.routes:insert {
      hosts = { "ws.test" },
      paths = { "/" },
      protocols = { "ws", "wss" },
      service = service,
    }

    bp.plugins:insert {
      name = "pre-function",
      service = service,
      config = RPC.plugin_conf(),
    }

    bp.plugins:insert {
      name = "post-function",
      service = service,
      config = {
        -- set frame limits from query args in the request
        ws_handshake = {[[
          local ws = kong.websocket

          local client = kong.request.get_query_arg("client_max_payload")
          client = tonumber(client)
          if client then
            ws.client.set_max_payload_size(client)
          end

          local upstream = kong.request.get_query_arg("upstream_max_payload")
          upstream = tonumber(upstream)
          if upstream then
            ws.upstream.set_max_payload_size(upstream)
          end
        ]]},
        ws_upstream_frame = {[[
          local ws = kong.websocket.upstream
          local data, typ, status = ws.get_frame()

          local ctx = kong.ctx

          if ctx.plugin.replace_data then
            ws.set_frame_data(ctx.plugin.replace_data)
            ctx.plugin.replace_data = nil
            return
          end

          if ctx.shared.update_handler then
            local updated = ctx.shared.update_handler(data)
            ctx.shared.update_handler = nil
            ws.set_frame_data(updated)
          end
        ]]},
      },
    }

    assert(helpers.start_kong({
      database = strategy,
      plugins  = "pre-function,post-function",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      untrusted_lua = "on",
      log_level = "debug",
    }, nil, nil, { http_mock = { ws = ws.mock_upstream() } }))
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  describe("phases", function()
    describe("ws_handshake", function()
      it("can use kong.response.set_header", function()
        local res = handshake({ host = "ws.test" })

        local header = assert.response(res).has_header("ws-function-test")
        assert.equals("hello", header)
      end)

      for sender in pairs(PEERS) do
        local src = sender == "client" and WS.client or WS.server
        local dst = sender == "client" and WS.server or WS.client

      describe(sender .. ".set_max_payload_size()", function()
        local session

        after_each(function()
          if session then session:close() end
        end)

        local function start_session(limit)
          helpers.clean_logfile()
          session = ws_session({
            host = "ws.test",
            query = {
              [sender .. "_max_payload"] = limit,
            },
          })
        end

        it("sets limits for text frames", function()
          local limit = 1024
          start_session(limit)

          session:assert({
            src.send.text(rep("1", limit + 1)),
            src.recv.close(nil, TOO_BIG.CODE),
            dst.recv.close(),
          })
        end)

        it("sets limits for binary frames", function()
          local limit = 1024
          start_session(limit)

          session:assert({
            src.send.binary(rep("1", limit + 1)),
            src.recv.close(nil, TOO_BIG.CODE),
            dst.recv.close(),
          })
        end)

        it("sets limits for aggregated frames", function()
          local limit = 1024
          start_session(limit)

          local frame = rep("1", limit / 4)
          session:assert({
            src.send.text_fragment(frame),
            src.send.continue(frame),
            src.send.continue(frame),

            -- sanity
            src.send.ping("marco"),
            dst.recv.ping("marco"),
            dst.send.pong("polo"),
            src.recv.pong("polo"),

            src.send.continue(frame .. "1"),

            src.recv.close(nil, TOO_BIG.CODE),
            dst.recv.close(),
          })
        end)

        it("throws an error if called during other phases", function()
          start_session()

          local fn = ("kong.websocket.%s.set_max_payload_size"):format(sender)

          session:assert({
            RPC.client.call(fn, 1024),
            src.recv.close(SERVER_ERROR.REASON, SERVER_ERROR.CODE),
            dst.recv.close(SERVER_ERROR.REASON, SERVER_ERROR.CODE),
          })
        end)
      end)
      end
    end)

    describe("ws_client_frame / ws_upstream_frame", function()
      local session
      before_each(function()
        helpers.clean_logfile()
        session = ws_session({
          host = "ws.test",
          query = { foo = "bar" },
          timeout = 50,
        })
        session.server_echo = true

        session:assert({
          WS.echo.text("sanity"),
        })
      end)

      after_each(function()
        if session then
          session:close()
        end
      end)

      describe("non-WS PDK functions", function()

        it("allows kong.response.get_* methods", function()
          session:assert({
            RPC.client.call("kong.response.get_status"),
            WS.server.recv.text("101"),

            RPC.client.call("kong.response.get_source"),
            WS.server.echo(),
            WS.client.recv.text("service"),

            RPC.client.call("kong.response.get_header", "connection"),
            WS.server.echo(),
            WS.client.recv.text("upgrade"),
          })
        end)

        it("allows kong.request.get_* methods", function()
          session:assert({
            RPC.client.call("kong.request.get_scheme"),
            WS.server.recv.text("http"),

            RPC.client.call("kong.request.get_host"),
            WS.server.recv.text("ws.test"),

            RPC.client.call("kong.request.get_port"),
            WS.server.recv.text("9000"),

            RPC.client.call("kong.request.get_path"),
            WS.server.recv.text("/session/client"),

            RPC.client.call("kong.request.get_query_arg", "foo"),
            WS.server.recv.text("bar"),
          })
        end)

        it("can use kong.ctx.plugin", function()
          session:assert({
            RPC.client.eval("kong.ctx.plugin.foo = 1"),
            WS.server.recv.any(),

            RPC.client.eval("return kong.ctx.plugin.foo"),
            WS.server.recv.text("1"),

            RPC.client.eval("kong.ctx.plugin.foo = kong.ctx.plugin.foo + 10"),
            WS.server.recv.any(),

            RPC.client.eval("return kong.ctx.plugin.foo"),
            WS.server.recv.text("11"),
          })
        end)

        it("can share kong.ctx.plugin across frame handlers", function()
          session:assert({
            RPC.client.eval("kong.ctx.plugin.test = 1"),
            WS.server.recv.any(),

            RPC.upstream.next.eval("kong.ctx.plugin.test = kong.ctx.plugin.test + 10"),
            WS.server.send.text("hi"),
            WS.client.recv.text("hi"),

            RPC.client.eval("return kong.ctx.plugin.test"),
            WS.server.recv.text("11"),
          })
        end)

        it("isolates kong.ctx.plugin", function()
          session:assert({
            RPC.client.eval([[
              kong.ctx.plugin.replace_data = 'replaced'
              kong.websocket.client.set_frame_data('test')
            ]]),
            WS.server.recv.text("test"),

            RPC.client.eval("return kong.ctx.plugin.replace_data"),
            WS.server.echo(),
            WS.client.recv.text("replaced"),
          })
        end)
      end)

      describe("get_frame()", function()
        it("returns frame data, type", function()
          session:assert({
            RPC.client.next.eval([[
              local data, typ = kong.websocket.client.get_frame()
              kong.ctx.plugin.data_last = data
              kong.ctx.plugin.type_last = typ
            ]]),

            WS.client.send.text("hello!"),
            WS.server.recv.text("hello!"),

            RPC.client.eval([[
              kong.websocket.client.set_frame_data(
                string.format("data: %s, type: %s",
                  kong.ctx.plugin.data_last,
                  kong.ctx.plugin.type_last
              ))
            ]]),

            WS.server.recv.text("data: hello!, type: text"),
          })
        end)
      end)

      describe("set_frame_data()", function()
        it("updates the frame payload", function()
          session:assert({
            RPC.client.next.call("kong.websocket.client.set_frame_data", "replaced!"),
            WS.client.send.text("don't replace me, bro"),
            WS.server.recv.text("replaced!"),

            RPC.upstream.next.call("kong.websocket.upstream.set_frame_data", "replaced!"),
            WS.server.send.text("I shall not be replaced"),
            WS.client.recv.text("replaced!"),
          })
        end)

        it("updates the payload for other plugins", function()
          session:assert({
            RPC.client.eval([[
              kong.ctx.shared.update_handler = function(data)
                return "<" .. data .. ">"
              end
            ]]),
            WS.server.recv.any(),

            RPC.upstream.next.call("kong.websocket.upstream.set_frame_data", "updated"),

            WS.server.send.text("original"),
            WS.client.recv.text("<updated>"),
          })

        end)
      end)

      describe("drop_frame()", function()
        it("causes a frame to be dropped", function()
          session:assert({
            WS.echo.text("1"),

            RPC.client.next.call("kong.websocket.client.drop_frame"),
            WS.client.send.text("dropped"),
            WS.client.send.text("2"),
            WS.server.recv.text("2"),

            RPC.upstream.next.call("kong.websocket.upstream.drop_frame"),
            WS.server.send.text("dropped"),
            WS.server.send.text("3"),
            WS.client.recv.text("3"),
          })
        end)

        it("throws an error on attempt to drop a close frame", function()
          session:assert({
            RPC.client.next.call("kong.websocket.client.drop_frame"),

            WS.client.send.close("goodbye", 1000),

            WS.client.recv.close(SERVER_ERROR.REASON, SERVER_ERROR.CODE),
            WS.server.recv.close(SERVER_ERROR.REASON, SERVER_ERROR.CODE),
          })

        end)
      end)

      describe("close()", function()
        it("closes the connection", function()
          session:assert({
            WS.echo.text("hi!"),
            RPC.client.call("kong.websocket.client.close",
                               1002, "goodbye, client!",
                               1001, "goodbye, upstream!"),
            WS.client.recv.close("goodbye, client!", 1002),
            WS.server.recv.close("goodbye, upstream!", 1001),
          })
        end)
      end)

      describe("set_status()", function()
        it("can update the status code in a close frame", function()
          session:assert({
            RPC.upstream.next.eval([[
              kong.websocket.upstream.set_frame_data("later, gator")
              kong.websocket.upstream.set_status(1009)
            ]]),

            WS.server.send.close("goodbye", 1001),
            WS.client.recv.close("later, gator", 1009),
          })
        end)

        it("requires a number as input", function()
          session:assert({
            RPC.upstream.next.eval([[
              kong.websocket.upstream.set_frame_data("later, gator")
              kong.websocket.upstream.set_status("NOPE")
            ]]),

            WS.server.send.close("goodbye", 1000),
            WS.client.recv.close(SERVER_ERROR.REASON, SERVER_ERROR.CODE),
            WS.server.recv.close(SERVER_ERROR.REASON, SERVER_ERROR.CODE),
          })
        end)

        it("throws an error if executed for non-close frames", function()
          session:assert({
            RPC.upstream.next.eval([[
              kong.websocket.upstream.set_frame_data("later, gator")
              kong.websocket.upstream.set_status(1002)
            ]]),

            WS.server.send.text("yello"),
            WS.client.recv.close(SERVER_ERROR.REASON, SERVER_ERROR.CODE),
            WS.server.recv.close(SERVER_ERROR.REASON, SERVER_ERROR.CODE),
          })
        end)
      end)

      describe("errors", function()
        it("terminates the connection on error", function()
          session:assert({
            WS.echo.text("hi!"),
            RPC.client.eval("error('oops')"),

            WS.client.recv.close(SERVER_ERROR.REASON, SERVER_ERROR.CODE),
            WS.server.recv.close(SERVER_ERROR.REASON, SERVER_ERROR.CODE),
          })
        end)
      end)

      describe("validation", function()
        it("client functions can't be called in ws_upstream_frame", function()
          session:assert({
            RPC.upstream.call("kong.websocket.client.get_frame"),
            WS.server.echo(),
            WS.client.recv.close(SERVER_ERROR.REASON, SERVER_ERROR.CODE),
            WS.server.recv.close(SERVER_ERROR.REASON, SERVER_ERROR.CODE),
          })
        end)

        it("upstream functions can't be called in ws_client_frame", function()
          session:assert({
            RPC.client.call("kong.websocket.upstream.get_frame"),
            WS.client.recv.close(SERVER_ERROR.REASON, SERVER_ERROR.CODE),
            WS.server.recv.close(SERVER_ERROR.REASON, SERVER_ERROR.CODE),
          })
        end)
      end)
    end)

    describe("ws_close", function()
      local session

      before_each(function()
        helpers.clean_logfile()
        session = ws_session({
          host = "ws.test",
          query = { foo = "bar" },
          timeout = 50,
        })
        session.server_echo = true

        session:assert({
          WS.echo.text("sanity"),
        })
      end)

      after_each(function()
        if session then
          session:close()
        end
      end)

      it("can share kong.ctx.plugin with other handlers", function()
        local fname, write_file = RPC.file_writer("kong.ctx.plugin.test")

        session:assert({
          RPC.upstream.next.eval("kong.ctx.plugin.test = 1"),
          WS.echo.text("1"),

          RPC.client.next.eval("kong.ctx.plugin.test = kong.ctx.plugin.test + 10"),
          WS.echo.text("2"),

          RPC.close.eval(write_file),

          WS.close(),
        })

        assert_file_contents(fname, "11")
      end)

      it("can use kong.log.serialize", function()
        local fname, write_file = RPC.log_writer()

        session:assert({
          RPC.upstream.next.call("kong.log.set_serialize_value", "ws_upstream", "upstream!"),
          WS.echo.text("1"),

          RPC.client.next.call("kong.log.set_serialize_value", "ws_client", "client!"),
          WS.echo.text("2"),

          RPC.close.eval(write_file),

          WS.close(),
        })

        await_file(fname)
        local content = pl_file.read(fname)
        local json = cjson.decode(content)
        assert.equals("upstream!", json.ws_upstream)
        assert.equals("client!", json.ws_client)
      end)
    end)

  end)
end)
end
