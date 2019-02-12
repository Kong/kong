local client = require "resty.websocket.client"
local helpers = require "spec.helpers"
local cjson = require "cjson"

for _, strategy in helpers.each_strategy() do
  describe("Websockets [#" .. strategy .. "]", function()
    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
      })

      local service = bp.services:insert {
        name = "ws",
        path = "/ws",
      }

      bp.routes:insert {
        protocols   = { "http" },
        paths       = { "/up-ws" },
        service     = service,
        strip_path  = true,
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    local function open_socket(uri)
      local wc = assert(client:new())
      assert(wc:connect(uri))
      return wc
    end

    describe("text", function()
      local function send_text_and_get_echo(uri)
        local payload = { message = "hello websocket" }
        local wc      = open_socket(uri)

        assert(wc:send_text(cjson.encode(payload)))
        local frame, typ, err = wc:recv_frame()
        assert.is_nil(wc.fatal)
        assert(frame, err)
        assert.equal("text", typ)
        assert.same(payload, cjson.decode(frame))

        assert(wc:send_close())
      end

      it("sends and gets text without Kong", function()
        send_text_and_get_echo("ws://127.0.0.1:15555/ws")
      end)

      it("sends and gets text with Kong", function()
        send_text_and_get_echo("ws://" .. helpers.get_proxy_ip(false) ..
                               ":" .. helpers.get_proxy_port(false) .. "/up-ws")
      end)

      it("sends and gets text with kong under HTTPS", function()
        send_text_and_get_echo("wss://" .. helpers.get_proxy_ip(true) ..
                               ":" .. helpers.get_proxy_port(true) .. "/up-ws")
      end)
    end)

    describe("ping pong", function()
      local function send_ping_and_get_pong(uri)
        local payload = { message = "give me a pong" }
        local wc      = open_socket(uri)

        assert(wc:send_ping(cjson.encode(payload)))
        local frame, typ, err = wc:recv_frame()
        assert.is_nil(wc.fatal)
        assert(frame, err)
        assert.equal("pong", typ)
        assert.same(payload, cjson.decode(frame))

        assert(wc:send_close())
      end

      it("plays ping-pong without Kong", function()
        send_ping_and_get_pong("ws://127.0.0.1:15555/ws")
      end)

      it("plays ping-pong with Kong", function()
        send_ping_and_get_pong("ws://" .. helpers.get_proxy_ip(false) ..
                               ":" .. helpers.get_proxy_port(false) .. "/up-ws")
      end)

      it("plays ping-pong with kong under HTTPS", function()
        send_ping_and_get_pong("wss://" .. helpers.get_proxy_ip(true) ..
                               ":" .. helpers.get_proxy_port(true) .. "/up-ws")
      end)
    end)
  end)
end
