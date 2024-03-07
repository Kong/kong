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
local cjson      = require "cjson"

local fmt = string.format
local STATUS = ws.const.status

local PEERS = {
  client = "upstream",
  upstream = "client",
}

local TYPES = {
  text = "binary",
  binary = "text",
}

describe("websocket-validator", function()
  lazy_setup(function()
    local bp = helpers.get_db_utils(
      "off",
      {
        "routes",
        "services",
        "plugins",
      },
      { "websocket-validator" }
    )


    local service = bp.services:insert {
      name = "ws",
      protocol = "ws",
      port = ws.const.ports.ws,
    }

    for peer in pairs(PEERS) do
      for typ in pairs(TYPES) do
        local route = bp.routes:insert {
          protocols= { "ws" },
          hosts = { fmt("%s.%s.ws.test", peer, typ) },
          service = service,
        }

        assert(bp.plugins:insert({
          name = "websocket-validator",
          route = route,
          config = {
            [peer] = {
              [typ] = {
                type = "draft4",
                schema = cjson.encode({
                  title = "my json schema",
                  type = "object",
                  properties = {
                    attr = { type = "string" },
                  },
                  required = { "attr" },
                }),
              },
            },
          },
        }))
      end
    end

    assert(helpers.start_kong({
      database = "off",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      log_level = "debug",
      plugins = "websocket-validator",
    }, nil, nil, { http_mock = { ws = ws.mock_upstream() } }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  for sender, peer in pairs(PEERS) do
    local src = sender == "client" and action.client or action.server
    local dst = sender == "client" and action.server or action.client

    for typ, other in pairs(TYPES) do

      describe(fmt("(%s -> %s) %s validation", sender, peer, typ), function()
        local session
        before_each(function()
          helpers.clean_logfile()
          session = ws_session({
            host = fmt("%s.%s.ws.test", sender, typ),
          })
        end)

        after_each(function()
          if session then
            session:close()
          end
        end)

        it("allows valid data", function()
          local frame = cjson.encode({
            attr = "my attribute",
          })

          session:assert({
            src.send[typ](frame),
            dst.recv[typ](frame),
          })
        end)

        it("rejects data that does not match the schema", function()
          local frame = cjson.encode({
            attr = 123,
          })

          session:assert({
            src.send[typ](frame),
            src.recv.close(nil, STATUS.INVALID_DATA.CODE),
            dst.recv.close(),
          })
        end)

        it("rejects invalid json", function()
          local frame = "NO!"
          session:assert({
            src.send[typ](frame),
            src.recv.close(nil, STATUS.INVALID_DATA.CODE),
            dst.recv.close(),
          })
        end)

        it("rejects empty frames", function()
          session:assert({
            src.send[typ](""),
            src.recv.close(nil, STATUS.INVALID_DATA.CODE),
            dst.recv.close(),
          })
        end)

        it("allows " .. peer .. " to send any kind of data", function()
          session:assert({
            dst.send[typ]("hiya!"),
            src.recv[typ]("hiya!"),
            dst.send[typ](cjson.encode({ "non-conforming... " })),
            src.recv[typ](cjson.encode({ "non-conforming... " })),
          })
        end)

        it("allows all " .. other .. " frames", function()
          session:assert({
            src.send[other]("other"),
            dst.recv[other]("other"),

            dst.send[other]("yello"),
            src.recv[other]("yello"),
          })
        end)
      end)
    end
  end
end)
