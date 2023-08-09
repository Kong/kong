local helpers = require "spec.helpers"
local cjson   = require "cjson"
local pretty  = require "pl.pretty"

local fmt = string.format

local function get_span(name, spans)
  for _, span in ipairs(spans) do
    if span.name == name then
      return span
    end
  end
end

local function assert_has_span(name, spans)
  local span = get_span(name, spans)
  assert.is_truthy(span, fmt("\nExpected to find %q span in:\n%s\n",
                             name, pretty.write(spans)))
  return span
end

local function assert_has_no_span(name, spans)
  local found = get_span(name, spans)
  assert.is_falsy(found, fmt("\nExpected not to find %q span in:\n%s\n",
                             name, pretty.write(spans)))
end

local function assert_has_attributes(span, attributes)
  for k, v in pairs(attributes) do
    assert.is_not_nil(span.attributes[k], fmt(
          "Expected span to have attribute %s, but got %s\n", k, pretty.write(span.attributes)))
    assert.matches(v, span.attributes[k], fmt(
          "Expected span to have attribute %s with value matching %s, but got %s\n",
          k, v, span.attributes[k]))
  end
end

local TCP_PORT = 35001
local tcp_trace_plugin_name = "tcp-trace-exporter"
for _, strategy in helpers.each_strategy() do
  local proxy_client

  describe("tracing instrumentations spec #" .. strategy, function()

    local function setup_instrumentations(types, custom_spans)
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

      bp.routes:insert({ service = http_srv,
                         protocols = { "http" },
                         paths = { "/status" },
                         hosts = { "status" },
                         strip_path = false })

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
        tracing_sampling_rate = 1,
      })

      proxy_client = helpers.proxy_client()
    end

    describe("off", function ()
      lazy_setup(function()
        setup_instrumentations("off", false)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("contains no spans", function ()
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

      it("contains the expected database span", function ()
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

        local spans = cjson.decode(res)
        assert_has_span("kong", spans)
        assert_has_span("kong.database.query", spans)

        assert_has_no_span("kong.balancer", spans)
        assert_has_no_span("kong.dns", spans)
        assert_has_no_span("kong.router", spans)
        assert_has_no_span("kong.rewrite.plugin." .. tcp_trace_plugin_name, spans)
        assert_has_no_span("kong.header_filter.plugin." .. tcp_trace_plugin_name, spans)
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

        local spans = cjson.decode(res)
        assert_has_span("kong", spans)
        assert_has_span("kong.router", spans)

        assert_has_no_span("kong.balancer", spans)
        assert_has_no_span("kong.database.query", spans)
        assert_has_no_span("kong.dns", spans)
        assert_has_no_span("kong.rewrite.plugin." .. tcp_trace_plugin_name, spans)
        assert_has_no_span("kong.header_filter.plugin." .. tcp_trace_plugin_name, spans)
      end)
    end)

    describe("http_client", function ()
      lazy_setup(function()
        setup_instrumentations("http_client", true)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("contains the expected kong.internal.request span", function ()
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

        local spans = cjson.decode(res)
        assert_has_span("kong", spans)
        assert_has_span("kong.internal.request", spans)

        assert_has_no_span("kong.balancer", spans)
        assert_has_no_span("kong.database.query", spans)
        assert_has_no_span("kong.dns", spans)
        assert_has_no_span("kong.rewrite.plugin." .. tcp_trace_plugin_name, spans)
        assert_has_no_span("kong.header_filter.plugin." .. tcp_trace_plugin_name, spans)
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

        local spans = cjson.decode(res)
        assert_has_span("kong", spans)
        assert_has_span("kong.balancer", spans)

        assert_has_no_span("kong.database.query", spans)
        assert_has_no_span("kong.dns", spans)
        assert_has_no_span("kong.router", spans)
        assert_has_no_span("kong.rewrite.plugin." .. tcp_trace_plugin_name, spans)
        assert_has_no_span("kong.header_filter.plugin." .. tcp_trace_plugin_name, spans)
      end)
    end)

    describe("plugin_rewrite", function ()
      lazy_setup(function()
        setup_instrumentations("plugin_rewrite", false)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("contains the expected kong.rewrite.plugin span", function ()
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

        local spans = cjson.decode(res)
        assert_has_span("kong", spans)
        assert_has_span("kong.rewrite.plugin." .. tcp_trace_plugin_name, spans)

        assert_has_no_span("kong.balancer", spans)
        assert_has_no_span("kong.database.query", spans)
        assert_has_no_span("kong.router", spans)
        assert_has_no_span("kong.dns", spans)
        assert_has_no_span("kong.header_filter.plugin." .. tcp_trace_plugin_name, spans)
      end)
    end)

    describe("plugin_header_filter", function ()
      lazy_setup(function()
        setup_instrumentations("plugin_header_filter", false)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("contains the expected kong.header_filter.plugin span", function ()
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
        assert_has_span("kong", spans)
        assert_has_span("kong.header_filter.plugin." .. tcp_trace_plugin_name, spans)

        assert_has_no_span("kong.balancer", spans)
        assert_has_no_span("kong.database.query", spans)
        assert_has_no_span("kong.router", spans)
        assert_has_no_span("kong.dns", spans)
        assert_has_no_span("kong.rewrite.plugin." .. tcp_trace_plugin_name, spans)
      end)
    end)


    describe("dns_query", function ()
      lazy_setup(function()
        setup_instrumentations("dns_query", true)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("contains the expected kong.dns span", function ()
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

        local spans = cjson.decode(res)
        assert_has_span("kong", spans)
        assert_has_span("kong.dns", spans)

        assert_has_no_span("kong.balancer", spans)
        assert_has_no_span("kong.database.query", spans)
        assert_has_no_span("kong.router", spans)
        assert_has_no_span("kong.rewrite.plugin." .. tcp_trace_plugin_name, spans)
        assert_has_no_span("kong.header_filter.plugin." .. tcp_trace_plugin_name, spans)
      end)
    end)

    describe("all", function ()
      lazy_setup(function()
        setup_instrumentations("all", true)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("contains all spans", function ()
        local thread = helpers.tcp_server(TCP_PORT)
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "status",
          }
        })
        assert.res_status(200, r)

        -- Getting back the TCP server input
        local ok, res = thread:join()
        assert.True(ok)
        assert.is_string(res)

        local spans = cjson.decode(res)
        local kong_span = assert_has_span("kong", spans)
        local dns_span = assert_has_span("kong.dns", spans)
        local balancer_span = assert_has_span("kong.balancer", spans)
        local db_span = assert_has_span("kong.database.query", spans)
        local int_req_span = assert_has_span("kong.internal.request", spans)
        assert_has_span("kong.router", spans)
        assert_has_span("kong.rewrite.plugin." .. tcp_trace_plugin_name, spans)
        assert_has_span("kong.header_filter.plugin." .. tcp_trace_plugin_name, spans)

        -- span attributes check
        assert_has_attributes(kong_span, {
          ["http.method"]    = "GET",
          ["http.url"]       = "http://status/status/200",
          ["http.route"]     = "/status",
          ["http.host"]      = "status",
          ["http.scheme"]    = "http",
          ["http.flavor"]    = "1.1",
          ["http.client_ip"] = "127.0.0.1",
          ["net.peer.ip"]    = "127.0.0.1",
        })

        assert_has_attributes(dns_span, {
          ["dns.record.domain"] = "[%w\\.]+",
          ["dns.record.ip"] = "[%d\\.]+",
          ["dns.record.port"] = "%d+"
        })

        assert_has_attributes(balancer_span, {
          ["net.peer.ip"] = "127.0.0.1",
          ["net.peer.port"] = "%d+",
          ["net.peer.name"]  = "127.0.0.1",
        })

        assert_has_attributes(db_span, {
          ["db.statement"] = ".*",
          ["db.system"] = "%w+",
        })

        assert_has_attributes(int_req_span, {
          ["http.method"]    = "GET",
          ["http.flavor"]    = "1.1",
          ["http.status_code"] = "200",
          ["http.url"] = "http[s]?://.*",
          ["http.user_agent"] = "[%w%s\\.]+"
        })
      end)
    end)

    describe("request", function ()
      lazy_setup(function()
        setup_instrumentations("request", false)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("contains the expected kong span", function ()
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

        local spans = cjson.decode(res)
        assert_has_span("kong", spans)
      end)
    end)
  end)
end
