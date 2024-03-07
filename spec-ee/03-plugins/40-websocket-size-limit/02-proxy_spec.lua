-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local helpers    = require "spec.helpers"
local ws         = require "spec-ee.fixtures.websocket"
local action     = require "spec-ee.fixtures.websocket.action"
local ws_session = require "spec-ee.fixtures.websocket.session"

local fmt = string.format
local rep = string.rep
local TOO_BIG = ws.const.status.MESSAGE_TOO_BIG

local PEERS = {
  client = "upstream",
  upstream = "client",
}

-- setting this lower than the max control frame size (125) so we can
-- easily validate that control frames are not affected
local LIMIT = 64


describe("Plugin: websocket-size-limit (ws_proxy)", function()
  lazy_setup(function()
    local bp = helpers.get_db_utils(
      "off",
      {
        "routes",
        "services",
        "plugins",
      },
      { "websocket-size-limit" }
    )


    local service = bp.services:insert {
      name = "ws",
      protocol = "ws",
      port = ws.const.ports.ws,
    }

    for peer in pairs(PEERS) do
      local route = assert(bp.routes:insert({
        protocols= { "ws" },
        hosts = { fmt("%s.ws.test", peer) },
        service = service,
      }))

      assert(bp.plugins:insert({
        name = "websocket-size-limit",
        route = route,
        config = {
          [peer .. "_max_payload"] = LIMIT,
        },
      }))
    end

    assert(helpers.start_kong({
      database = "off",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "websocket-size-limit",
    }, nil, nil, { http_mock = { ws = ws.mock_upstream() } }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  for sender, peer in pairs(PEERS) do
    local src = sender == "client" and action.client or action.server
    local dst = sender == "client" and action.server or action.client

    describe(fmt("(%s)", peer), function()
      local session
      before_each(function()
        helpers.clean_logfile()
        session = ws_session({
          host = fmt("%s.ws.test", sender),
        })
      end)

      after_each(function()
        if session then
          session:close()
        end
      end)

      it("allows data frames under/at the limit to pass through", function()
        local frame = rep("1", LIMIT)
        session:assert({
          src.send.text(frame),
          dst.send.text(frame),

          src.send.binary(frame),
          dst.send.binary(frame),
        })
      end)

      it("limits singular text frames", function()
        session:assert({
          src.send.text(rep("1", LIMIT + 1)),
          src.recv.close(nil, TOO_BIG.CODE),
          dst.recv.close(),
        })
      end)

      it("limits singular binary frames", function()
        session:assert({
          src.send.binary(rep("1", LIMIT + 1)),
          src.recv.close(nil, TOO_BIG.CODE),
          dst.recv.close(),
        })
      end)

      it("allows control frames to exceed the limit", function()
        local frame = rep("1", LIMIT + 1)
        session:assert({
          src.send.ping(frame),
          dst.recv.ping(frame),

          src.send.pong(frame),
          dst.recv.pong(frame),

          src.send.close(frame, 1000),
          dst.recv.close(frame, 1000),
        })
      end)

      it("allows aggregated frames if their total size is under the limit", function()
        local frame = rep("1", LIMIT / 4)
        session:assert({
          src.send.text_fragment(frame),
          src.send.continue(frame),
          src.send.continue(frame),
          src.send.final_fragment(frame),

          dst.recv.text(rep(frame, 4)),

          src.send.binary_fragment(frame),
          src.send.continue(frame),
          src.send.continue(frame),
          src.send.final_fragment(frame),

          dst.recv.binary(rep(frame, 4)),
        })
      end)

      it("limits aggregated text frames", function()
        local frame = rep("1", LIMIT / 4)
        session:assert({
          src.send.text_fragment(frame),
          src.send.continue(frame),
          src.send.continue(frame),
          src.send.final_fragment(frame .. "1"),

          src.recv.close(nil, TOO_BIG.CODE),
          dst.recv.close(),
        })
      end)

      it("limits aggregated binary frames", function()
        local frame = rep("1", LIMIT / 4)
        session:assert({
          src.send.binary_fragment(frame),
          src.send.continue(frame),
          src.send.continue(frame),
          src.send.final_fragment(frame .. "1"),

          src.recv.close(nil, TOO_BIG.CODE),
          dst.recv.close(),
        })
      end)
    end)
  end
end)
