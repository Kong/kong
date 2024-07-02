local helpers = require "spec.helpers"
local cjson   = require "cjson"
local join    = require "pl.stringx".join


local TCP_PORT = helpers.get_available_port()
local tcp_trace_plugin_name = "tcp-trace-exporter"


local function get_parent(span, spans)
  for _, s in ipairs(spans) do
    if s.span_id == span.parent_id then
      return s
    end
  end
end

for _, strategy in helpers.each_strategy() do
  local proxy_client

  describe("tracer pdk spec #" .. strategy, function()

    local function setup_instrumentations(types, custom_spans, sampling_rate)
      local bp, _ = assert(helpers.get_db_utils(strategy, {
        "services",
        "routes",
        "plugins",
      }, { tcp_trace_plugin_name }))

      local http_srv = assert(bp.services:insert {
        name = "mock-service",
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
      })

      bp.routes:insert({ service = http_srv,
                         protocols = { "http" },
                         paths = { "/" }})

      bp.plugins:insert({
        name = tcp_trace_plugin_name,
        config = {
          host = "127.0.0.1",
          port = TCP_PORT,
          custom_spans = custom_spans or false,
        }
      })

      assert(helpers.start_kong {
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "tcp-trace-exporter",
        tracing_instrumentations = types,
        tracing_sampling_rate = sampling_rate or 1,
      })

      proxy_client = helpers.proxy_client()
    end

    describe("sampling rate", function ()
      local instrumentations = { "request", "router", "balancer" }
      lazy_setup(function()
        setup_instrumentations(join(",", instrumentations), false, 0.5)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("results in either all or none of the spans in a trace to be sampled", function ()
        for _ = 1, 100 do
          local thread = helpers.tcp_server(TCP_PORT)
          local r = assert(proxy_client:send {
            method  = "GET",
            path    = "/",
          })
          assert.res_status(200, r)

          local ok, res = thread:join()
          assert.True(ok)
          assert.is_string(res)

          local spans = cjson.decode(res)
          assert.True(#spans == 0 or #spans == #instrumentations)
        end
      end)
    end)

    describe("spans start/end times are consistent with their hierarchy", function ()
      lazy_setup(function()
        setup_instrumentations("all", false, 1)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("sets child lifespan within parent's lifespan", function ()
        for _ = 1, 100 do
          local thread = helpers.tcp_server(TCP_PORT)
          local r = assert(proxy_client:send {
            method  = "GET",
            path    = "/",
          })
          assert.res_status(200, r)

          local ok, res = thread:join()
          assert.True(ok)
          assert.is_string(res)

          local spans = cjson.decode(res)
          for i = 2, #spans do -- skip the root span (no parent)
            local span = spans[i]
            local parent = get_parent(span, spans)
            assert.is_not_nil(parent)
            assert.True(span.start_time_ns >= parent.start_time_ns)
            assert.True(span.end_time_ns <= parent.end_time_ns)
          end
        end
      end)
    end)
  end)
end
