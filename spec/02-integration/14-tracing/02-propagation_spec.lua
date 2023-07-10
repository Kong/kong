local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"
local to_hex = require("resty.string").to_hex

local rand_bytes = utils.get_rand_bytes

local TCP_PORT = 35001

local function gen_id(len)
  return to_hex(rand_bytes(len))
end

for _, strategy in helpers.each_strategy() do
  local proxy_client

  describe("tracing propagation spec #" .. strategy, function()
    lazy_setup(function()
      local bp, _ = assert(helpers.get_db_utils(strategy, {
        "routes",
        "plugins",
      }, { "tcp-trace-exporter", "trace-propagator" }))

      bp.routes:insert({
        hosts = { "propagate.test" },
      })

      bp.plugins:insert({
        name = "tcp-trace-exporter",
        config = {
          host = "127.0.0.1",
          port = TCP_PORT,
          custom_spans = false,
        }
      })

      bp.plugins:insert({
        name = "trace-propagator"
      })
    end)

    describe("spans hierarchy", function ()
      lazy_setup(function()
        assert(helpers.start_kong {
          database = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
          plugins = "tcp-trace-exporter,trace-propagator",
          tracing_instrumentations = "balancer",
          tracing_sampling_rate = 1,
        })
        proxy_client = helpers.proxy_client()
      end)

      lazy_teardown(function()
        if proxy_client then
          proxy_client:close()
        end
        helpers.stop_kong()
      end)

      it("propagates the balancer span", function ()
        local thread = helpers.tcp_server(TCP_PORT)
        local r = assert(proxy_client:send {
          method  = "GET",
          path = "/request",
          headers = {
            ["Host"] = "propagate.test",
          }
        })
        assert.res_status(200, r)
        local body = r:read_body()
        body = assert(body and cjson.decode(body))

        local ok, res = thread:join()
        assert.True(ok)
        assert.is_string(res)

        -- expected spans are returned
        local spans = cjson.decode(res)
        assert.is_same(2, #spans, res)
        local balancer_span = spans[2]
        assert.is_same("kong.balancer", balancer_span.name)

        local traceparent = assert(body.headers.traceparent)
        local trace_id = balancer_span.trace_id
        local span_id = balancer_span.span_id
        -- traceparent contains correct trace id and the balancer span's id
        assert.equals("00-" .. trace_id .. "-" .. span_id .. "-01", traceparent)
      end)
    end)

    describe("parsing incoming headers", function ()
      local trace_id = gen_id(16)
      local span_id = gen_id(8)

      lazy_setup(function()
        assert(helpers.start_kong {
          database = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
          plugins = "tcp-trace-exporter,trace-propagator",
          tracing_instrumentations = "request,router,balancer,plugin_access,plugin_header_filter",
          tracing_sampling_rate = 1,
        })
        proxy_client = helpers.proxy_client()
      end)

      lazy_teardown(function()
        if proxy_client then
          proxy_client:close()
        end
        helpers.stop_kong()
      end)

      it("enables sampling when incoming header has sampled enabled", function ()
        local thread = helpers.tcp_server(TCP_PORT)
        local r = assert(proxy_client:send {
          method  = "GET",
          path = "/request",
          headers = {
            ["Host"] = "propagate.test",
            traceparent = string.format("00-%s-%s-01", trace_id, span_id),
          }
        })
        assert.res_status(200, r)
        local body = r:read_body()
        body = assert(body and cjson.decode(body))

        local ok, res = thread:join()
        assert.True(ok)
        assert.is_string(res)

        -- all spans are returned
        local spans = cjson.decode(res)
        assert.is_same(6, #spans, res)

        local traceparent = assert(body.headers.traceparent)
        assert.matches("00%-" .. trace_id .. "%-%x+%-01", traceparent)
      end)

      it("disables sampling when incoming header has sampled disabled", function ()
        local thread = helpers.tcp_server(TCP_PORT)
        local r = assert(proxy_client:send {
          method  = "GET",
          path = "/request",
          headers = {
            ["Host"] = "propagate.test",
            traceparent = string.format("00-%s-%s-00", trace_id, span_id),
          }
        })
        assert.res_status(200, r)
        local body = r:read_body()
        body = assert(body and cjson.decode(body))

        local ok, res = thread:join()
        assert.True(ok)
        assert.is_string(res)

        -- no spans are returned
        local spans = cjson.decode(res)
        assert.is_same(0, #spans, res)

        local traceparent = assert(body.headers.traceparent)
        assert.matches("00%-" .. trace_id .. "%-%x+%-00", traceparent)
      end)
    end)
  end)
end
