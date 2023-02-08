local helpers = require "spec.helpers"
local cjson = require "cjson"

local TCP_PORT = 35001
local tcp_trace_plugin_name = "tcp-trace-exporter"
for _, strategy in helpers.each_strategy() do
  local proxy_client

  describe("tracing instrumentations spec #" .. strategy, function()

    local function setup_instrumentations(types, custom_spans, extra)
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

      local conf = {
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "tcp-trace-exporter",
        tracing_instrumentations = types,
      }

      if extra then
        for k, v in pairs(extra) do
          conf[k] = v
        end
      end

      assert(helpers.start_kong(conf))
      proxy_client = helpers.proxy_client()
    end

    describe("configuration", function()
      local types = { "db_query", "router", "balancer" }
      local rate = 0.5

      after_each(function()
        helpers.stop_kong()
      end)

      local function validate()
        local conf
        helpers.pwait_until(function()
          local admin = helpers.admin_client()
          local res = admin:get("/")
          assert.res_status(200, res)

          local body = assert.response(res).has.jsonbody()
          admin:close()

          conf = body.configuration
        end, 5)

        assert.same(types, conf.tracing_instrumentations)
        assert.same(types, conf.opentelemetry_tracing)

        assert.equal(rate, conf.tracing_sampling_rate)
        assert.equal(rate, conf.opentelemetry_tracing_sampling_rate)
      end

      it("updates the new fields from the old ones", function()
        setup_instrumentations(nil, false, {
          opentelemetry_tracing = table.concat(types, ","),
          opentelemetry_tracing_sampling_rate = tostring(rate),
        })

        validate()
      end)

      it("updates the old fields from the new ones", function()
        setup_instrumentations(nil, false, {
          tracing_instrumentations = table.concat(types, ","),
          tracing_sampling_rate = tostring(rate),
        })

        validate()
      end)


    end)

    describe("off", function ()
      lazy_setup(function()
        setup_instrumentations("off", false)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("works", function ()
        local thread = helpers.tcp_server(TCP_PORT)
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
        })
        assert.res_status(200, r)

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

      it("works", function ()
        local thread = helpers.tcp_server(TCP_PORT)
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
        })
        assert.res_status(200, r)

        -- Getting back the TCP server input
        local ok, res = thread:join()
        assert.True(ok)
        assert.is_string(res)

        -- Making sure it's alright
        local spans = cjson.decode(res)
        local expected_span_num = 2
        -- cassandra has different db query implementation
        if strategy == "cassandra" then
          expected_span_num = 4
        end
        assert.is_same(expected_span_num, #spans, res)
        assert.is_same("query", spans[2].name)
      end)
    end)

    describe("router", function ()
      lazy_setup(function()
        setup_instrumentations("router", false)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("works", function ()
        local thread = helpers.tcp_server(TCP_PORT)
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
        })
        assert.res_status(200, r)

        -- Getting back the TCP server input
        local ok, res = thread:join()
        assert.True(ok)
        assert.is_string(res)

        -- Making sure it's alright
        local spans = cjson.decode(res)
        assert.is_same(2, #spans, res)
        assert.is_same("router", spans[2].name)
      end)
    end)

    describe("http_client", function ()
      lazy_setup(function()
        setup_instrumentations("http_client", true)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("works", function ()
        local thread = helpers.tcp_server(TCP_PORT)
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
        })
        assert.res_status(200, r)

        -- Getting back the TCP server input
        local ok, res = thread:join()
        assert.True(ok)
        assert.is_string(res)

        -- Making sure it's alright
        local spans = cjson.decode(res)
        assert.is_same(4, #spans, res)
        assert.is_same("GET /", spans[1].name)
      end)
    end)

    describe("balancer", function ()
      lazy_setup(function()
        setup_instrumentations("balancer", false)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("works", function ()
        local thread = helpers.tcp_server(TCP_PORT)
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
        })
        assert.res_status(200, r)

        -- Getting back the TCP server input
        local ok, res = thread:join()
        assert.True(ok)
        assert.is_string(res)

        -- Making sure it's alright
        local spans = cjson.decode(res)
        assert.is_same(2, #spans, res)
        assert.is_same("balancer try #1", spans[2].name)
      end)
    end)

    describe("plugin_rewrite", function ()
      lazy_setup(function()
        setup_instrumentations("plugin_rewrite", false)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("works", function ()
        local thread = helpers.tcp_server(TCP_PORT)
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
        })
        assert.res_status(200, r)

        -- Getting back the TCP server input
        local ok, res = thread:join()
        assert.True(ok)
        assert.is_string(res)

        -- Making sure it's alright
        local spans = cjson.decode(res)
        assert.is_same(2, #spans, res)
        assert.is_same("rewrite phase: " .. tcp_trace_plugin_name, spans[2].name)
      end)
    end)

    describe("plugin_header_filter", function ()
      lazy_setup(function()
        setup_instrumentations("plugin_header_filter", false)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("works", function ()
        local thread = helpers.tcp_server(TCP_PORT)
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
        })
        assert.res_status(200, r)

        -- Getting back the TCP server input
        local ok, res = thread:join()
        assert.True(ok)
        assert.is_string(res)

        -- Making sure it's alright
        local spans = cjson.decode(res)
        assert.is_same(2, #spans, res)
        assert.is_same("header_filter phase: " .. tcp_trace_plugin_name, spans[2].name)
      end)
    end)


    describe("dns_query", function ()
      lazy_setup(function()
        setup_instrumentations("dns_query", true)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("works", function ()
        local thread = helpers.tcp_server(TCP_PORT)
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
        })
        assert.res_status(200, r)

        -- Getting back the TCP server input
        local ok, res = thread:join()
        assert.True(ok)
        assert.is_string(res)

        -- Making sure it's alright
        local spans = cjson.decode(res)
        -- If the db host if a domain, it creates extra db query
        assert.is_true(#spans >= 4, res)

        local found
        for _, span in ipairs(spans) do
          if span.name == "DNS: konghq.com" then
            found = true
          end
        end

        assert.is_true(found, res)
      end)
    end)

    describe("all", function ()
      lazy_setup(function()
        setup_instrumentations("all", true)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("works", function ()
        local thread = helpers.tcp_server(TCP_PORT)
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
        })
        assert.res_status(200, r)

        -- Getting back the TCP server input
        local ok, res = thread:join()
        assert.True(ok)
        assert.is_string(res)

        -- Making sure it's alright
        local spans = cjson.decode(res)
        local expected_span_num = 12
        -- cassandra has different db query implementation
        if strategy == "cassandra" then
          expected_span_num = expected_span_num + 4
        end

        assert.is_same(expected_span_num, #spans, res)
      end)
    end)

    describe("request", function ()
      lazy_setup(function()
        setup_instrumentations("request", false)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("works", function ()
        local thread = helpers.tcp_server(TCP_PORT)
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
        })
        assert.res_status(200, r)

        -- Getting back the TCP server input
        local ok, res = thread:join()
        assert.True(ok)
        assert.is_string(res)

        -- Making sure it's alright
        local spans = cjson.decode(res)
        assert.is_same(1, #spans, res)
      end)
    end)
  end)
end
