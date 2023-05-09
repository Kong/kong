-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local helpers    = require "spec.helpers"
local ws         = require "spec-ee.fixtures.websocket"
local ee_helpers = require "spec-ee.helpers"
local cjson      = require "cjson"

local fmt = string.format

local TCP_PORT = 35001

local function send_ws()
  local thread = helpers.tcp_server(TCP_PORT)
  local conn = assert(ee_helpers.ws_proxy_client({
    scheme = "ws",
    path = "/",
    host = "ws.test",
  }))
  assert(conn:send_text("hello instrumentation"))
  assert(conn:recv_frame())
  assert(conn:send_close())
  conn:close()
  return thread
end

for _, strategy in helpers.each_strategy() do
  describe(fmt("#%s WebSocket instrumentation", strategy), function()
    local function setup_instrumentations(types)
      local bp = helpers.get_db_utils(
        strategy,
        {
          "routes",
          "services",
          "plugins",
        },
        { "tcp-trace-exporter", "pre-function" }
      )

      local service = assert(bp.services:insert({
        name  = "ws.test",
        protocol = "ws",
      }))

      local route = assert(bp.routes:insert({
        name  = "ws.test",
        hosts = { "ws.test" },
        protocols = { "ws" },
        service = service,
      }))

      assert(bp.plugins:insert {
        name = "tcp-trace-exporter",
        route = route,
        protocols = { "ws" },
        config = {
          host = "127.0.0.1",
          port = TCP_PORT,
          custom_spans = false,
        },
      })

      assert(bp.plugins:insert {
        name = "pre-function",
        route = route,
        protocols = { "ws" },
        config = {
          ws_handshake = {[[
            -- execute a DB query to make sure we have a kong.database.query span
            kong.db.routes:select({ id = ngx.ctx.route.id })
          ]]}
        },
      })

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled,tcp-trace-exporter",
        tracing_instrumentations = types,
        tracing_sampling_rate = 1,
      }, nil, nil, { http_mock = { ws = ws.mock_upstream() } }))
    end

    describe("off", function ()
      lazy_setup(function()
        setup_instrumentations("off", false)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("contains no spans", function ()
        local thread = send_ws()

        -- Getting back the TCP server input
        local ok, res = thread:join()
        assert.True(ok)
        assert.is_string(res)

        -- Making sure it's alright
        local spans = cjson.decode(res)
        assert.is_same(0, #spans, res)
      end)
    end)

    describe("db_query", function ()
      lazy_setup(function()
        setup_instrumentations("db_query", false)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("contains the expected db spans", function ()
        local thread = send_ws()

        -- Getting back the TCP server input
        local ok, res = thread:join()
        assert.True(ok)
        assert.is_string(res)

        -- Making sure it's alright
        local spans = cjson.decode(res)
        local expected_span_num = 2

        assert.is_same(expected_span_num, #spans, res)
        assert.is_same("kong.database.query", spans[2].name)
      end)
    end)

    describe("router", function ()
      lazy_setup(function()
        setup_instrumentations("router", false)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("contains the expected router span", function ()
        local thread = send_ws()

        -- Getting back the TCP server input
        local ok, res = thread:join()
        assert.True(ok)
        assert.is_string(res)

        -- Making sure it's alright
        local spans = cjson.decode(res)
        assert.is_same(2, #spans, res)
        assert.is_same("kong.router", spans[2].name)
      end)
    end)

    describe("balancer", function ()
      lazy_setup(function()
        setup_instrumentations("balancer", false)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("contains the expected balancer span", function ()
        local thread = send_ws()

        local ok, res = thread:join()
        assert.True(ok)
        assert.is_string(res)

        -- expected spans are returned
        local spans = cjson.decode(res)
        assert.is_same(2, #spans, res)
        local balancer_span = spans[2]
        assert.is_same("kong.balancer", balancer_span.name)
      end)
    end)

    describe("dns_query", function ()
      lazy_setup(function()
        setup_instrumentations("dns_query", true)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("contains the expected dns span", function ()
        local thread = send_ws()

        -- Getting back the TCP server input
        local ok, res = thread:join()
        assert.True(ok)
        assert.is_string(res)

        -- Making sure it's alright
        local spans = cjson.decode(res)

        local found
        for _, span in ipairs(spans) do
          if span.name == "kong.dns" then
            found = true
          end
        end

        assert.is_true(found, res)
      end)
    end)

    describe("request", function ()
      lazy_setup(function()
        setup_instrumentations("request", false)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("contains the expected kong root span", function ()
        local thread = send_ws()

        -- Getting back the TCP server input
        local ok, res = thread:join()
        assert.True(ok)
        assert.is_string(res)

        -- Making sure it's alright
        local spans = cjson.decode(res)
        assert.is_same(1, #spans, res)
      end)
    end)

    describe("all", function ()
      lazy_setup(function()
        setup_instrumentations("all", true)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("contains all the expected spans", function ()
        local thread = send_ws()

        -- Getting back the TCP server input
        local ok, res = thread:join()
        assert.True(ok)
        assert.is_string(res)

        -- Making sure it's alright
        local spans = cjson.decode(res)
        assert.is_true(#spans >= 6, res)
      end)
    end)
  end)
end
