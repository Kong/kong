require "kong.observability.otlp.proto"
local helpers = require "spec.helpers"
local pb = require "pb"
local pl_file = require "pl.file"
local ngx_re = require "ngx.re"
local to_hex = require "resty.string".to_hex
local get_rand_bytes = require("kong.tools.rand").get_rand_bytes
local table_merge = require("kong.tools.table").table_merge

local fmt = string.format

local HTTP_MOCK_TIMEOUT = 1

local function gen_trace_id()
  return to_hex(get_rand_bytes(16))
end

local function gen_span_id()
  return to_hex(get_rand_bytes(8))
end

-- so we can have a stable output to verify
local function sort_by_key(tbl)
  return table.sort(tbl, function(a, b)
    return a.key < b.key
  end)
end

local HTTP_SERVER_PORT_TRACES = helpers.get_available_port()
local HTTP_SERVER_PORT_LOGS = helpers.get_available_port()
local PROXY_PORT = 9000

local post_function_access_body =
    [[kong.log.info("this is a log from kong.log");
    ngx.log(ngx.INFO, "this is a log from ngx.log")]]

for _, strategy in helpers.each_strategy() do
  describe("opentelemetry exporter #" .. strategy, function()
    local bp

    lazy_setup(function ()
      -- overwrite for testing
      pb.option("enum_as_value")
      pb.option("auto_default_values")
    end)

    lazy_teardown(function()
      -- revert it back
      pb.option("enum_as_name")
      pb.option("no_default_values")
    end)

    -- helpers
    local function setup_instrumentations(types, config, fixtures, router_scoped, service_scoped, another_global, global_sampling_rate)
      local http_srv = assert(bp.services:insert {
        name = "mock-service",
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
      })

      local http_srv2 = assert(bp.services:insert {
        name = "mock-service2",
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
      })

      local route = assert(bp.routes:insert({ service = http_srv,
                                              protocols = { "http" },
                                              paths = { "/" }}))

      local logs_route = assert(bp.routes:insert({ service = http_srv,
                                                   protocols = { "http" },
                                                   paths = { "/logs" }}))

      local logs_traces_route = assert(bp.routes:insert({ service = http_srv,
                                                   protocols = { "http" },
                                                   paths = { "/traces_logs" }}))

      assert(bp.routes:insert({ service = http_srv2,
                                protocols = { "http" },
                                paths = { "/no_plugin" }}))

      assert(bp.plugins:insert({
        name = "opentelemetry",
        route = router_scoped and route,
        service = service_scoped and http_srv,
        config = table_merge({
          traces_endpoint = "http://127.0.0.1:" .. HTTP_SERVER_PORT_TRACES,
          batch_flush_delay = 0, -- report immediately
        }, config)
      }))

      assert(bp.plugins:insert({
        name = "opentelemetry",
        route = logs_traces_route,
        config = table_merge({
          traces_endpoint = "http://127.0.0.1:" .. HTTP_SERVER_PORT_TRACES,
          logs_endpoint = "http://127.0.0.1:" .. HTTP_SERVER_PORT_LOGS,
          queue = {
            max_batch_size = 1000,
            max_coalescing_delay = 2,
          },
        }, config)
      }))

      assert(bp.plugins:insert({
        name = "opentelemetry",
        route = logs_route,
        config = table_merge({
          logs_endpoint = "http://127.0.0.1:" .. HTTP_SERVER_PORT_LOGS,
          queue = {
            max_batch_size = 1000,
            max_coalescing_delay = 2,
          },
        }, config)
      }))

      assert(bp.plugins:insert({
        name = "post-function",
        route = logs_traces_route,
        config = {
          access = { post_function_access_body },
        },
      }))

      assert(bp.plugins:insert({
        name = "post-function",
        route = logs_route,
        config = {
          access = { post_function_access_body },
        },
      }))

      if another_global then
        assert(bp.plugins:insert({
          name = "opentelemetry",
          config = table_merge({
            traces_endpoint = "http://127.0.0.1:" .. HTTP_SERVER_PORT_TRACES,
            batch_flush_delay = 0, -- report immediately
          }, config)
        }))
      end

      assert(helpers.start_kong({
        proxy_listen = "0.0.0.0:" .. PROXY_PORT,
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "opentelemetry,post-function",
        tracing_instrumentations = types,
        tracing_sampling_rate = global_sampling_rate or 1,
      }, nil, nil, fixtures))
    end

    describe("valid #http request", function ()
      local mock_traces, mock_logs
      lazy_setup(function()
        bp, _ = assert(helpers.get_db_utils(strategy, {
          "services",
          "routes",
          "plugins",
        }, { "opentelemetry" }))

        setup_instrumentations("all", {
          headers = {
            ["X-Access-Token"] = "token",
          },
        })
        mock_traces = helpers.http_mock(HTTP_SERVER_PORT_TRACES, { timeout = HTTP_MOCK_TIMEOUT })
        mock_logs = helpers.http_mock(HTTP_SERVER_PORT_LOGS, { timeout = HTTP_MOCK_TIMEOUT })
      end)

      lazy_teardown(function()
        helpers.stop_kong()
        if mock_traces then
          mock_traces("close", true)
        end
        if mock_logs then
          mock_logs("close", true)
        end
      end)

      it("exports valid traces", function ()
        local headers, body
        helpers.wait_until(function()
          local cli = helpers.proxy_client(7000, PROXY_PORT)
          local r = assert(cli:send {
            method  = "GET",
            path    = "/",
          })
          assert.res_status(200, r)

          cli:close()

          local lines
          lines, body, headers = mock_traces()

          return lines
        end, 10)

        assert.is_string(body)

        assert.equals(headers["Content-Type"], "application/x-protobuf")

        -- custom http headers
        assert.equals(headers["X-Access-Token"], "token")

        local decoded = assert(pb.decode("opentelemetry.proto.collector.trace.v1.ExportTraceServiceRequest", body))
        assert.not_nil(decoded)

        -- array is unstable
        local res_attr = decoded.resource_spans[1].resource.attributes
        sort_by_key(res_attr)
        -- default resource attributes
        assert.same("service.instance.id", res_attr[1].key)
        assert.same("service.name", res_attr[2].key)
        assert.same({string_value = "kong", value = "string_value"}, res_attr[2].value)
        assert.same("service.version", res_attr[3].key)
        assert.same({string_value = kong.version, value = "string_value"}, res_attr[3].value)

        local scope_spans = decoded.resource_spans[1].scope_spans
        assert.is_true(#scope_spans > 0, scope_spans)
      end)

      local function assert_find_valid_logs(body, request_id, trace_id)
        local decoded = assert(pb.decode("opentelemetry.proto.collector.logs.v1.ExportLogsServiceRequest", body))
        assert.not_nil(decoded)

        -- array is unstable
        local res_attr = decoded.resource_logs[1].resource.attributes
        sort_by_key(res_attr)
        -- default resource attributes
        assert.same("service.instance.id", res_attr[1].key)
        assert.same("service.name", res_attr[2].key)
        assert.same({string_value = "kong", value = "string_value"}, res_attr[2].value)
        assert.same("service.version", res_attr[3].key)
        assert.same({string_value = kong.version, value = "string_value"}, res_attr[3].value)

        local scope_logs = decoded.resource_logs[1].scope_logs
        assert.is_true(#scope_logs > 0, scope_logs)

        local found = 0
        for _, scope_log in ipairs(scope_logs) do
          local log_records = scope_log.log_records
          for _, log_record in ipairs(log_records) do
            local logline = log_record.body.string_value

            -- filter the right log lines
            if string.find(logline, "this is a log") then
              assert(logline:sub(-7) == "ngx.log" or logline:sub(-8) == "kong.log", logline)

              assert.is_table(log_record.attributes)
              local found_attrs = {}
              for _, attr in ipairs(log_record.attributes) do
                found_attrs[attr.key] = attr.value[attr.value.value]
              end

              -- ensure the log is from the current request
              if found_attrs["request.id"] == request_id then
                local expected_line
                if logline:sub(-8) == "kong.log" then
                  expected_line = 1
                else
                  expected_line = 2
                end

                assert.is_number(log_record.time_unix_nano)
                assert.is_number(log_record.observed_time_unix_nano)
                assert.equals(post_function_access_body, found_attrs["introspection.source"])
                assert.equals(expected_line, found_attrs["introspection.current.line"])
                assert.equals(log_record.severity_number, 9)
                assert.equals(log_record.severity_text, "INFO")
                if trace_id then
                  assert.equals(trace_id, to_hex(log_record.trace_id))
                  assert.is_string(log_record.span_id)
                  assert.is_number(log_record.flags)
                end

                found = found + 1
                if found == 2 then
                  break
                end
              end
            end
          end
        end
        assert.equals(2, found)
      end

      it("exports valid logs with tracing", function ()
        local trace_id = gen_trace_id()

        local headers, body, request_id

        local cli = helpers.proxy_client(7000, PROXY_PORT)
        local res = assert(cli:send {
          method  = "GET",
          path    = "/traces_logs",
          headers = {
            traceparent = fmt("00-%s-0123456789abcdef-01", trace_id),
          },
        })
        assert.res_status(200, res)
        cli:close()

        request_id = res.headers["X-Kong-Request-Id"]

        helpers.wait_until(function()
          local lines
          lines, body, headers = mock_logs()

          return lines
        end, 10)

        assert.is_string(body)
        assert.equals(headers["Content-Type"], "application/x-protobuf")
        assert_find_valid_logs(body, request_id, trace_id)
      end)

      it("exports valid logs without tracing", function ()
        local headers, body, request_id

        local cli = helpers.proxy_client(7000, PROXY_PORT)
        local res = assert(cli:send {
          method  = "GET",
          path    = "/logs",
        })
        assert.res_status(200, res)
        cli:close()

        request_id = res.headers["X-Kong-Request-Id"]

        helpers.wait_until(function()
          local lines
          lines, body, headers = mock_logs()

          return lines
        end, 10)

        assert.is_string(body)
        assert.equals(headers["Content-Type"], "application/x-protobuf")

        assert_find_valid_logs(body, request_id)
      end)
    end)

    -- this test is not meant to check that the sampling rate is applied
    -- precisely (we have unit tests for that), but rather that the config
    -- option is properly handled by the plugin and has an effect on the 
    -- sampling decision.
    for _, global_sampling_rate in ipairs{ 0, 0.001, 1} do
      describe("With config.sampling_rate set, using global sampling rate: " .. global_sampling_rate, function ()
        local mock
        local sampling_rate = 0.5
         -- this trace_id is always sampled with 0.5 rate
        local sampled_trace_id = "92a54b3e1a7c4f2da9e44b8a6f3e1dab"
         -- this trace_id is never sampled with 0.5 rate
        local non_sampled_trace_id = "4bf92f3577b34da6a3ce929d0e0e4736"

        lazy_setup(function()
          bp, _ = assert(helpers.get_db_utils(strategy, {
            "services",
            "routes",
            "plugins",
          }, { "opentelemetry" }))

          setup_instrumentations("all", {
            sampling_rate = sampling_rate,
          }, nil, nil, nil, nil, global_sampling_rate)
          mock = helpers.http_mock(HTTP_SERVER_PORT_TRACES, { timeout = HTTP_MOCK_TIMEOUT })
        end)

        lazy_teardown(function()
          helpers.stop_kong()
          if mock then
            mock("close", true)
          end
        end)

        it("does not sample spans when trace_id == non_sampled_trace_id", function()
          local cli = helpers.proxy_client(7000, PROXY_PORT)
          local r = assert(cli:send {
            method  = "GET",
            path    = "/",
            headers = {
              traceparent = "00-" .. non_sampled_trace_id .. "-0123456789abcdef-01"
            }
          })
          assert.res_status(200, r)

          cli:close()

          ngx.sleep(2)
          local lines = mock()
          assert.is_falsy(lines)
        end)

        it("samples spans when trace_id == sampled_trace_id", function ()
          local body
          helpers.wait_until(function()
            local cli = helpers.proxy_client(7000, PROXY_PORT)
            local r = assert(cli:send {
              method  = "GET",
              path    = "/",
              headers = {
                traceparent = "00-" .. sampled_trace_id .. "-0123456789abcdef-01"
              }
            })
            assert.res_status(200, r)

            cli:close()

            local lines
            lines, body = mock()
            return lines
          end, 10)

          local decoded = assert(pb.decode("opentelemetry.proto.collector.trace.v1.ExportTraceServiceRequest", body))
          assert.not_nil(decoded)
          local scope_spans = decoded.resource_spans[1].scope_spans
          assert.is_true(#scope_spans > 0, scope_spans)
        end)
      end)
    end


    describe("With config.sampling_rate unset, using global sampling rate: 0.5", function ()
      local mock
      local sampling_rate = 0.5
       -- this trace_id is always sampled with 0.5 rate
      local sampled_trace_id = "92a54b3e1a7c4f2da9e44b8a6f3e1dab"
       -- this trace_id is never sampled with 0.5 rate
      local non_sampled_trace_id = "4bf92f3577b34da6a3ce929d0e0e4736"

      lazy_setup(function()
        bp, _ = assert(helpers.get_db_utils(strategy, {
          "services",
          "routes",
          "plugins",
        }, { "opentelemetry" }))

        setup_instrumentations("all", {}, nil, nil, nil, nil, sampling_rate)
        mock = helpers.http_mock(HTTP_SERVER_PORT_TRACES, { timeout = HTTP_MOCK_TIMEOUT })
      end)

      lazy_teardown(function()
        helpers.stop_kong()
        if mock then
          mock("close", true)
        end
      end)

      it("does not sample spans when trace_id == non_sampled_trace_id", function()
        local cli = helpers.proxy_client(7000, PROXY_PORT)
        local r = assert(cli:send {
          method  = "GET",
          path    = "/",
          headers = {
            traceparent = "00-" .. non_sampled_trace_id .. "-0123456789abcdef-01"
          }
        })
        assert.res_status(200, r)

        cli:close()

        ngx.sleep(2)
        local lines = mock()
        assert.is_falsy(lines)
      end)

      it("samples spans when trace_id == sampled_trace_id", function ()
        for _ = 1, 10 do
          local body
          helpers.wait_until(function()
            local cli = helpers.proxy_client(7000, PROXY_PORT)
            local r = assert(cli:send {
              method  = "GET",
              path    = "/",
              headers = {
                traceparent = "00-" .. sampled_trace_id .. "-0123456789abcdef-01"
              }
            })
            assert.res_status(200, r)

            cli:close()

            local lines
            lines, body = mock()
            return lines
          end, 10)

          local decoded = assert(pb.decode("opentelemetry.proto.collector.trace.v1.ExportTraceServiceRequest", body))
          assert.not_nil(decoded)
          local scope_spans = decoded.resource_spans[1].scope_spans
          assert.is_true(#scope_spans > 0, scope_spans)
        end
      end)
    end)

    for _, case in ipairs{
      {true, true, true},
      {true, true, nil},
      {true, nil, true},
      {true, nil, nil},
      {nil, true, true},
      {nil, true, nil},
    } do
      describe("#scoping for" .. (case[1] and " route" or "")
                              .. (case[2] and " service" or "")
                              .. (case[3] and " with global" or "")
      , function ()
        local mock
        lazy_setup(function()
          bp, _ = assert(helpers.get_db_utils(strategy, {
            "services",
            "routes",
            "plugins",
          }, { "opentelemetry" }))

          setup_instrumentations("all", {
            headers = {
              ["X-Access-Token"] = "token",
            },
          }, nil, case[1], case[2], case[3])
          mock = helpers.http_mock(HTTP_SERVER_PORT_TRACES, { timeout = HTTP_MOCK_TIMEOUT })
        end)

        lazy_teardown(function()
          helpers.stop_kong()
          if mock then
            mock("close", true)
          end
        end)

        it("works", function ()
          local cli = helpers.proxy_client(7000, PROXY_PORT)
          local r = assert(cli:send {
            method  = "GET",
            path    = "/no_plugin",
          })
          assert.res_status(200, r)

          cli:close()

          local lines, err = mock()

          -- we should only have telemetry reported from the global plugin
          if case[3] then
            assert(lines, err)

          else
            assert.is_falsy(lines)
            assert.matches("timeout", err)
          end
        end)
      end)
    end
    describe("overwrite resource attributes #http", function ()
      local mock
      lazy_setup(function()
        bp, _ = assert(helpers.get_db_utils(strategy, {
          "services",
          "routes",
          "plugins",
        }, { "opentelemetry" }))

        setup_instrumentations("all", {
          resource_attributes = {
            ["service.name"] = "kong_oss",
            ["os.version"] = "debian",
          }
        })
        mock = helpers.http_mock(HTTP_SERVER_PORT_TRACES, { timeout = HTTP_MOCK_TIMEOUT })
      end)

      lazy_teardown(function()
        helpers.stop_kong()
        if mock then
          mock("close", true)
        end
      end)

      it("works", function ()
        local headers, body
        helpers.wait_until(function()
          local cli = helpers.proxy_client(7000, PROXY_PORT)
          local r = assert(cli:send {
            method  = "GET",
            path    = "/",
          })
          assert.res_status(200, r)

          cli:close()

          local lines
          lines, body, headers = mock()

          return lines
        end, 10)

        assert.is_string(body)

        assert.equals(headers["Content-Type"], "application/x-protobuf")

        local decoded = assert(pb.decode("opentelemetry.proto.collector.trace.v1.ExportTraceServiceRequest", body))
        assert.not_nil(decoded)

        -- array is unstable
        local res_attr = decoded.resource_spans[1].resource.attributes
        sort_by_key(res_attr)
        -- resource attributes
        assert.same("os.version", res_attr[1].key)
        assert.same({string_value = "debian", value = "string_value"}, res_attr[1].value)
        assert.same("service.instance.id", res_attr[2].key)
        assert.same("service.name", res_attr[3].key)
        assert.same({string_value = "kong_oss", value = "string_value"}, res_attr[3].value)
        assert.same("service.version", res_attr[4].key)
        assert.same({string_value = kong.version, value = "string_value"}, res_attr[4].value)

        local scope_spans = decoded.resource_spans[1].scope_spans
        assert.is_true(#scope_spans > 0, scope_spans)
      end)
    end)

    describe("data #race with cascaded multiple spans", function ()
      lazy_setup(function()
        bp, _ = assert(helpers.get_db_utils(strategy, {
          "services",
          "routes",
          "plugins",
        }, { "opentelemetry" }))

        pl_file.delete("/tmp/kong_opentelemetry_data")

        local fixtures = {
          http_mock = {}
        }

        fixtures.http_mock.my_server_block = [[
          server {
            server_name myserver;
            listen ]] .. HTTP_SERVER_PORT_TRACES .. [[;
            client_body_buffer_size 1024k;

            location / {
              content_by_lua_block {
                ngx.req.read_body()
                local data = ngx.req.get_body_data()

                local fd = assert(io.open("/tmp/kong_opentelemetry_data", "a"))
                assert(fd:write(ngx.encode_base64(data)))
                assert(fd:write("\n")) -- ensure last line ends in newline
                assert(fd:close())

                return 200;
              }
            }
          }
        ]]

        for i = 1, 5 do
          local svc = assert(bp.services:insert {
            host = "127.0.0.1",
            port = PROXY_PORT,
            path = i == 1 and "/" or ("/cascade-" .. (i - 1)),
          })

          bp.routes:insert({ service = svc,
                             protocols = { "http" },
                             paths = { "/cascade-" .. i },
                             strip_path = true })
        end

        setup_instrumentations("request", {}, fixtures)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("send enough spans", function ()
        local pb_set = {}
        local cli = helpers.proxy_client(7000, PROXY_PORT)
        local r = assert(cli:send {
          method  = "GET",
          path    = "/cascade-5",
        })
        assert.res_status(200, r)

        cli:close()

        helpers.wait_until(function()
          local fd, err = io.open("/tmp/kong_opentelemetry_data", "r")
          if err then
            return false, "failed to open file: " .. err
          end

          local body = fd:read("*a")
          pb_set = ngx_re.split(body, "\n")

          local count = 0
          for _, pb_data in ipairs(pb_set) do
            local decoded = assert(pb.decode("opentelemetry.proto.collector.trace.v1.ExportTraceServiceRequest", ngx.decode_base64(pb_data)))
            assert.not_nil(decoded)

            local scope_spans = decoded.resource_spans[1].scope_spans
            if scope_spans then
              for _, scope_span in ipairs(scope_spans) do
                count = count + #scope_span.spans
              end
            end
          end

          if count < 6 then
            return false, "not enough spans: " .. count
          end

          return true
        end, 10)
      end)
    end)

    describe("#propagation", function ()
      local mock
      lazy_setup(function()
        bp, _ = assert(helpers.get_db_utils(strategy, {
          "services",
          "routes",
          "plugins",
        }, { "opentelemetry" }))

        setup_instrumentations("request")
        mock = helpers.http_mock(HTTP_SERVER_PORT_TRACES, { timeout = HTTP_MOCK_TIMEOUT })
      end)

      lazy_teardown(function()
        helpers.stop_kong()
        if mock then
          mock("close", true)
        end
      end)

      it("#propagate w3c traceparent", function ()
        local trace_id = gen_trace_id()
        local parent_id = gen_span_id()
        local request_id

        local headers, body
        helpers.wait_until(function()
          local cli = helpers.proxy_client(7000, PROXY_PORT)
          local r = assert(cli:send {
            method  = "GET",
            path    = "/",
            headers = {
              ["traceparent"] = fmt("00-%s-%s-01", trace_id, parent_id),
            }
          })
          assert.res_status(200, r)

          cli:close()

          local lines
          lines, body, headers = mock()

          request_id = r.headers["X-Kong-Request-Id"]

          return lines
        end, 10)

        assert.is_string(body)

        assert.equals(headers["Content-Type"], "application/x-protobuf")

        local decoded = assert(pb.decode("opentelemetry.proto.collector.trace.v1.ExportTraceServiceRequest", body))
        assert.not_nil(decoded)

        local scope_span = decoded.resource_spans[1].scope_spans[1]
        local span = scope_span.spans[1]
        assert.same(trace_id, to_hex(span.trace_id), "trace_id")
        assert.same(parent_id, to_hex(span.parent_span_id), "parent_id")
        local attr = span.attributes
        sort_by_key(attr)
        assert.same({
          { key = "http.client_ip", value = { string_value = "127.0.0.1", value = "string_value" } },
          { key = "http.flavor", value = { string_value = "1.1", value = "string_value" } },
          { key = "http.host", value = { string_value = "0.0.0.0", value = "string_value" } },
          { key = "http.method", value = { string_value = "GET", value = "string_value" } },
          { key = "http.route", value = { string_value = "/", value = "string_value" } },
          { key = "http.scheme", value = { string_value = "http", value = "string_value" } },
          { key = "http.status_code", value = { int_value = 200, value = "int_value" } },
          { key = "http.url", value = { string_value = "http://0.0.0.0/", value = "string_value" } },
          { key = "kong.request.id", value = { string_value = request_id, value = "string_value" } },
          { key = "net.peer.ip", value = { string_value = "127.0.0.1", value = "string_value" } },
        }, attr)
      end)
    end)

    describe("#referenceable fields", function ()
      local mock
      lazy_setup(function()
        helpers.setenv("TEST_OTEL_ENDPOINT", "http://127.0.0.1:" .. HTTP_SERVER_PORT_TRACES)
        helpers.setenv("TEST_OTEL_ACCESS_KEY", "secret-1")
        helpers.setenv("TEST_OTEL_ACCESS_SECRET", "secret-2")

        bp, _ = assert(helpers.get_db_utils(strategy, {
          "services",
          "routes",
          "plugins",
        }, { "opentelemetry" }))

        setup_instrumentations("all", {
          endpoint = "{vault://env/test_otel_endpoint}",
          headers = {
            ["X-Access-Key"] = "{vault://env/test_otel_access_key}",
            ["X-Access-Secret"] = "{vault://env/test_otel_access_secret}",
          },
        })
        mock = helpers.http_mock(HTTP_SERVER_PORT_TRACES, { timeout = HTTP_MOCK_TIMEOUT })
      end)

      lazy_teardown(function()
        helpers.unsetenv("TEST_OTEL_ENDPOINT")
        helpers.unsetenv("TEST_OTEL_ACCESS_KEY")
        helpers.unsetenv("TEST_OTEL_ACCESS_SECRET")
        helpers.stop_kong()
        if mock then
          mock("close", true)
        end
      end)

      it("works", function ()
        local headers, body
        helpers.wait_until(function()
          local cli = helpers.proxy_client(7000, PROXY_PORT)
          local r = assert(cli:send {
            method  = "GET",
            path    = "/",
          })
          assert.res_status(200, r)

          cli:close()

          local lines
          lines, body, headers = mock()

          return lines
        end, 60)

        assert.is_string(body)

        assert.equals(headers["Content-Type"], "application/x-protobuf")

        -- dereferenced headers
        assert.equals(headers["X-Access-Key"], "secret-1")
        assert.equals(headers["X-Access-Secret"], "secret-2")
      end)
    end)
  end)
end
