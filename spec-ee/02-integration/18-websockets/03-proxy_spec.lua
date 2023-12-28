-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers    = require "spec.helpers"
local ee_helpers = require "spec-ee.helpers"
local ws         = require "spec-ee.fixtures.websocket"
local action     = require "spec-ee.fixtures.websocket.action"
local RPC        = require "spec-ee.fixtures.websocket.rpc"
local ws_session = require "spec-ee.fixtures.websocket.session"
local pl_path    = require "pl.path"
local const      = require "kong.enterprise_edition.constants"

local client, server = action.client, action.server

local function await_file(fname)
  helpers.wait_until(function()
    return pl_path.exists(fname) and pl_path.getsize(fname) > 0
  end, 5, 0.05)
end

describe("WebSocket proxying behavior", function()
  setup(function()
    local bp = helpers.get_db_utils(
      "off",
      {
        "routes",
        "services",
        "plugins",
      },
      { "pre-function" }
    )


    local service = bp.services:insert {
      name = "ws",
      protocol = "ws",
      port = ws.const.ports.ws,
    }

    bp.routes:insert {
      hosts = { "ws.test" },
      paths = { "/" },
      protocols = { "ws" },
      service = service,
    }

    bp.plugins:insert {
      name = "pre-function",
      service = service,
      config = RPC.plugin_conf({
        ws_handshake = {[[
            ngx.ctx.KONG_WEBSOCKET_JANITOR_TIMEOUT = 0.1
            ngx.ctx.KONG_WEBSOCKET_RECV_TIMEOUT = 100
            ngx.ctx.KONG_WEBSOCKET_SEND_TIMEOUT = 1000
            ngx.ctx.KONG_WEBSOCKET_LINGERING_TIME = 4000
            ngx.ctx.KONG_WEBSOCKET_LINGERING_TIMEOUT = 2000
            ngx.ctx.KONG_WEBSOCKET_DEBUG = true
        ]]},
      }),
    }

    assert(helpers.start_kong({
      database = "off",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      untrusted_lua = "on",
      log_level = "debug",
    }, nil, nil, { http_mock = { ws = ws.mock_upstream() } }))
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  local session
  local fname

  before_each(function()
    helpers.clean_logfile()

    session = ws_session({
      host = "ws.test",
      read_timeout = 1000,
      write_timeout = 1000,
      connect_timeout = 1000,
    })


    -- add a log writer hook to ws_close so we can verify that this handler
    -- has been invoked by checking if the file exists
    local write
    fname, write = RPC.log_writer()

    session:assert({
      server.echo.enable(),
      action.echo.text("sanity"),
      server.echo.disable(),
      RPC.close.eval(write),
    })
  end)

  after_each(function()
    session:close()
  end)

  describe("#extensions", function()
    it("strips extensions from the handshake request", function()
      local ws_client = ee_helpers.ws_proxy_client({
        host = "ws.test",
        headers = {
          "Sec-WebSocket-Extensions: foo",
          "sec-webSocket-extensions: bar",
        },
      })

      finally(function() ws_client:close() end)

      local req = ws_client:get_request()
      assert.is_table(req)
      assert.is_table(req.headers)
      assert.is_nil(req.headers["sec-websocket-extensions"])
    end)

    it("fails the connection if the upstream enables un-requested extensions", function()
      local sess = ws_session({
        host = "ws.test",
        fail_on_error = false,
        headers = {
          "x-mock-websocket-echo-sec-websocket-extensions: foo",
          "x-mock-websocket-echo-sec-websocket-extensions: bar",
        },
      })
      finally(function() sess:close() end)

      local status = ws.const.status.PROTOCOL_ERROR
      sess:assert({
        server.recv.close(status.REASON, status.CODE)
      })

      assert.equals(501, sess.client.response.status)
    end)
  end)

  describe("frame aggregation", function()
    it("aggregates client fragments", function()
      session:assert({
        action.set_recv_timeout(100),

        client.send.text_fragment("1"),
        server.recv.timeout(),

        client.send.continue("2"),
        server.recv.timeout(),

        client.send.continue("3"),
        client.send.final_fragment("4"),
        server.recv.text("1234"),
      })
    end)

    it("aggregates upstream fragments", function()
      session:assert({
        action.set_recv_timeout(100),

        server.send.text_fragment("1"),
        client.recv.timeout(),

        server.send.continue("2"),
        client.recv.timeout(),

        server.send.continue("3"),
        server.send.final_fragment("4"),
        client.recv.text("1234"),
      })
    end)

    it("forwards interleaved control frames", function()
      session:assert({
        client.send.text_fragment("a"),
        server.send.binary_fragment("1"),

        client.send.ping("marco"),
        server.recv.ping("marco"),
        server.send.pong("polo"),
        client.recv.pong("polo"),

        client.send.continue("b"),
        server.send.continue("2"),

        server.send.ping("marco"),
        client.recv.ping("marco"),
        client.send.pong("polo"),
        server.recv.pong("polo"),

        client.send.final_fragment("c"),
        server.send.final_fragment("3"),

        client.recv.binary("123"),
        server.recv.text("abc"),
      })
    end)
  end)

  describe("#exit", function()

    describe("(#client)", function()

      describe("close frame", function()
        it("forwards close frames to the server as-is", function()
          session:assert({
            client.send.close("goodbye", 1001),
            server.recv.close("goodbye", 1001),
          })
        end)

        it("terminates the ws_proxy phase and begins ws_close", function()
          session:assert({
            client.send.close("goodbye", 1001),
            server.recv.close("goodbye", 1001),

            server.send.close("later, dude", 1000),
            client.recv.close("later, dude", 1000),
          })

          await_file(fname)
        end)

        it("doesn't lose in-flight messages", function()
          session:assert({
            server.send.ping("ping"),
            server.send.text("1"),
            server.send.text("2"),

            client.send.close("client", 1001),
            server.recv.close("client", 1001),

            client.recv.ping("ping"),
            client.recv.text("1"),
            client.recv.text("2"),

            server.send.close("server", 1000),
            client.recv.close("server", 1000),
          })
        end)

        it("allows more messages from the server before closing", function()
          session:assert({
            client.send.close("client", 1001),
            server.recv.close("client", 1001),

            server.send.text("1"),
            server.send.text("2"),
            server.send.close("server", 1000),

            client.recv.text("1"),
            client.recv.text("2"),
            client.recv.close("server", 1000),
          })
        end)
      end)

      describe("abort", function()
        it("sends a close frame to the upstream", function()
          session:assert({
            client.close(),
            server.recv.close(nil, 1001),
          })
        end)

        it("terminates the ws_proxy phase and begins ws_close", function()
          session:assert({
            client.close(),
            server.recv.close(nil, 1001),
          })

          await_file(fname)
        end)
      end)
    end)

    describe("(#server)", function()
      describe("close frame", function()
        it("forwards close frames to the client as-is", function()
          session:assert({
            server.send.close("goodbye", 1001),
            client.recv.close("goodbye", 1001),
          })
        end)

        it("doesn't lose in-flight messages", function()
          session:assert({
            client.send.ping("ping"),
            client.send.text("1"),
            client.send.text("2"),

            server.send.close("server", 1001),
            client.recv.close("server", 1001),

            server.recv.ping("ping"),
            server.recv.text("1"),
            server.recv.text("2"),

            client.send.close("client", 1000),
            server.recv.close("client", 1000),
          })
        end)

        it("allows more messages from the client before closing", function()
          session:assert({
            server.send.close("server", 1001),
            client.recv.close("server", 1001),

            client.send.text("1"),
            client.send.text("2"),
            client.send.close("client", 1000),

            server.recv.text("1"),
            server.recv.text("2"),
            server.recv.close("client", 1000),
          })
        end)
      end)

      describe("abort", function()
        it("sends the client a close frame", function()
          session:assert({
            server.close(),
            client.recv.close(nil, 1001),
          })
        end)

        it("terminates the ws_proxy phase and begins ws_close", function()
          session:assert({
            server.close(),
            client.recv.close(nil, 1001),
          })

          await_file(fname)
        end)
      end)
    end)
  end)

  describe("#limits", function()
    local peers = {
      client = "upstream",
      upstream = "client",
    }

    for src, dst in pairs(peers) do
      local limit = src == "client"
                    and const.WEBSOCKET.DEFAULT_CLIENT_MAX_PAYLOAD
                    or const.WEBSOCKET.DEFAULT_UPSTREAM_MAX_PAYLOAD

      local ok = string.rep("1", limit)

      for _, excess in ipairs({ 1, 1024, 1024*1024, 1024*1024*8 }) do
        it("enforces a default limit on " .. src .. " frames " ..
           "(excess: " .. tostring(excess) .. ")", function()

          helpers.clean_logfile()

          local too_big = string.rep("1", limit + excess)

          session:assert({
            action.set_recv_timeout(5000),

            action[src].send.text(ok),
            action[dst].recv.text(ok),

            action[src].send.text(too_big),

            action[src].recv.close(nil, 1009),
            action[dst].recv.close(nil, 1001),
          })

          assert.logfile().has_line(src .. " recv.+ frame size exceeds limit .+, closing")
        end)
      end
    end
  end)

  describe("client handshake validation", function()
    local httpc

    before_each(function()
      httpc = helpers.proxy_client()
    end)

    after_each(function()
      if httpc then httpc:close() end
    end)

    local function assert_400(params, exp)
      local headers = params.headers or {}

      headers.host = "ws.test"

      local res = httpc:send({
        path = "/",
        method = params.method or "GET",
        headers = headers,
      })

      local body = assert.res_status(400, res)
      assert.matches(exp, body, nil, true)
    end

    it("rejects non-GET requests", function()
      assert_400({
        method = "POST",
        headers = {
          connection = "Upgrade",
          upgrade = "websocket",
          ["sec-websocket-key"] = "dGhlIHNhbXBsZSBub25jZQ==",
          ["sec-websocket-version"] = "13",
        }
      }, "invalid request method")
    end)

    it("rejects requests with no Connection header", function()
      assert_400({
        headers = {
          upgrade = "websocket",
          ["sec-websocket-key"] = "dGhlIHNhbXBsZSBub25jZQ==",
          ["sec-websocket-version"] = "13",
        }
      },"invalid/missing 'Connection' header")
    end)


    it("rejects requests with an invalid Connection header", function()
      assert_400({
        headers = {
          connection = "nope",
          upgrade = "websocket",
          ["sec-websocket-key"] = "dGhlIHNhbXBsZSBub25jZQ==",
          ["sec-websocket-version"] = "13",
        }
      }, "invalid/missing 'Connection' header")
    end)

    it("rejects requests with no Upgrade header", function()
      assert_400({
        headers = {
          connection = "upgrade",
          ["sec-websocket-key"] = "dGhlIHNhbXBsZSBub25jZQ==",
          ["sec-websocket-version"] = "13",
        }
      }, "invalid/missing 'Upgrade' header")
    end)

    it("rejects requests with an invalid Upgrade header", function()
      assert_400({
        headers = {
          upgrade = "nope",
          connection = "upgrade",
          ["sec-websocket-key"] = "dGhlIHNhbXBsZSBub25jZQ==",
          ["sec-websocket-version"] = "13",
        }
      }, "invalid/missing 'Upgrade' header")
    end)

    it("rejects requests with no Sec-WebSocket-Key header", function()
      assert_400({
        headers = {
          upgrade = "websocket",
          connection = "upgrade",
          ["sec-websocket-version"] = "13",
        }
      }, "invalid/missing 'Sec-WebSocket-Key' header")
    end)

    it("rejects requests with an invalid Sec-WebSocket-Key header", function()
      assert_400({
        headers = {
          upgrade = "websocket",
          connection = "upgrade",
          ["sec-websocket-key"] = { "dGhlIHNhbXBsZSBub25jZQ==",
                                    "dGhlIHNhbXBsZSBub25jZQ==", },
          ["sec-websocket-version"] = "13",
        }
      }, "invalid/missing 'Sec-WebSocket-Key' header")
    end)

    it("rejects requests with no Sec-WebSocket-Version header", function()
      assert_400({
        headers = {
          upgrade = "websocket",
          connection = "upgrade",
          ["sec-websocket-key"] = "dGhlIHNhbXBsZSBub25jZQ==",
        }
      }, "invalid/missing 'Sec-WebSocket-Version' header")
    end)

    it("rejects requests with an invalid Sec-WebSocket-Version header", function()
      assert_400({
        headers = {
          upgrade = "websocket",
          connection = "upgrade",
          ["sec-websocket-key"] = "dGhlIHNhbXBsZSBub25jZQ==",
          ["sec-websocket-version"] = "14",
        }
      }, "invalid/missing 'Sec-WebSocket-Version' header")

      assert_400({
        headers = {
          upgrade = "websocket",
          connection = "upgrade",
          ["sec-websocket-key"] = "dGhlIHNhbXBsZSBub25jZQ==",
          ["sec-websocket-version"] = { "13", "13" },
        }
      }, "invalid/missing 'Sec-WebSocket-Version' header")
    end)
  end)
end)
describe("(#proxy) close frame test when worker exiting", function()
  setup(function()
    local bp = helpers.get_db_utils(
      "off",
      {
        "routes",
        "services",
        "plugins",
      },
      { "pre-function" }
    )


    local service = bp.services:insert {
      name = "ws",
      protocol = "ws",
      port = ws.const.ports.ws,
    }

    bp.routes:insert {
      hosts = { "ws.test" },
      paths = { "/" },
      protocols = { "ws" },
      service = service,
    }

    bp.plugins:insert {
      name = "pre-function",
      service = service,
      config = RPC.plugin_conf({
        ws_handshake = {[[
            ngx.ctx.KONG_WEBSOCKET_JANITOR_TIMEOUT = 0.1
            ngx.ctx.KONG_WEBSOCKET_RECV_TIMEOUT = 100
            ngx.ctx.KONG_WEBSOCKET_SEND_TIMEOUT = 1000
            ngx.ctx.KONG_WEBSOCKET_LINGERING_TIME = 4000
            ngx.ctx.KONG_WEBSOCKET_LINGERING_TIMEOUT = 2000
            ngx.ctx.KONG_WEBSOCKET_DEBUG = true
        ]]},
      }),
    }

    assert(helpers.start_kong({
      database = "off",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      untrusted_lua = "on",
      log_level = "debug",
    }, nil, nil, { http_mock = { ws = ws.mock_upstream() } }))
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  local session
  local fname

  before_each(function()
    helpers.clean_logfile()

    session = ws_session({
      host = "ws.test",
      read_timeout = 1000,
      write_timeout = 1000,
      connect_timeout = 1000,
    })


    -- add a log writer hook to ws_close so we can verify that this handler
    -- has been invoked by checking if the file exists
    local write
    fname, write = RPC.log_writer()

    session:assert({
      server.echo.enable(),
      action.echo.text("sanity"),
      server.echo.disable(),
      RPC.close.eval(write),
    })
  end)

  after_each(function()
    session:close()
  end)

  it("it ends the session when the NGINX worker is stopping", function()
    local status = ws.const.status.GOING_AWAY

    --[[
      test janitor exiting logic
      (enterprise_edition/runloop/websocket.lua: janitor),
      but SIGHUP will not be successful in websocket proxy.
      Because worker will not exit until websocket closed
      no matter it is closed actively or passively.
    ]]
    assert(helpers.signal(nil, "-QUIT"))

    session:assert({
      action.set_recv_timeout(2000),
      client.recv.close(status.REASON, status.CODE),
      server.recv.close(status.REASON, status.CODE),
    })

    await_file(fname)
  end)
end)
