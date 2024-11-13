local helpers = require "spec.helpers"
local pb = require "pb"

local HTTP_SERVER_PORT_LOGS = helpers.get_available_port()


for _, strategy in helpers.each_strategy() do
  describe("kong.pdk.telemetry #" .. strategy, function()
    local bp
    local plugin_instance_name = "my-pdk-logger-instance"

    describe("log", function()
      describe("with OpenTelemetry", function()
        local mock_logs

        lazy_setup(function()
          bp, _ = assert(helpers.get_db_utils(strategy, {
            "services",
            "routes",
            "plugins",
          }, { "opentelemetry", "pdk-logger" }))

          local http_srv = assert(bp.services:insert {
            name = "mock-service",
            host = helpers.mock_upstream_host,
            port = helpers.mock_upstream_port,
          })

          local logs_route = assert(bp.routes:insert({
            service = http_srv,
            protocols = { "http" },
            paths = { "/logs" }
          }))

          assert(bp.plugins:insert({
            name = "opentelemetry",
            route = logs_route,
            config = {
              logs_endpoint = "http://127.0.0.1:" .. HTTP_SERVER_PORT_LOGS,
              queue = {
                max_batch_size = 1000,
                max_coalescing_delay = 2,
              },
            }
          }))

          assert(bp.plugins:insert({
            name = "pdk-logger",
            route = logs_route,
            config = {},
            instance_name = plugin_instance_name,
          }))

          assert(helpers.start_kong({
            database = strategy,
            nginx_conf = "spec/fixtures/custom_nginx.template",
            plugins = "opentelemetry,pdk-logger",
          }))

          mock_logs = helpers.http_mock(HTTP_SERVER_PORT_LOGS, { timeout = 1 })
        end)

        lazy_teardown(function()
          helpers.stop_kong()
          if mock_logs then
            mock_logs("close", true)
          end
        end)

        local function assert_find_valid_logs(body, request_id)
          local decoded = assert(pb.decode("opentelemetry.proto.collector.logs.v1.ExportLogsServiceRequest", body))
          assert.not_nil(decoded)

          local scope_logs = decoded.resource_logs[1].scope_logs
          assert.is_true(#scope_logs > 0, scope_logs)

          local found = 0
          for _, scope_log in ipairs(scope_logs) do
            local log_records = scope_log.log_records
            for _, log_record in ipairs(log_records) do
              -- from the pdk-logger plugin:
              local plugin_name = "pdk-logger"
              local attributes = {
                some_key = "some_value",
                some_other_key = "some_other_value"
              }
              local expected_messages_attributes = {
                access_phase = { message = "hello, access phase", attributes = attributes},
                header_filter_phase = { message = "hello, header_filter phase", attributes = {}},
                log_phase = { message = "", attributes = attributes},
                log_phase_2 = { message = "", attributes = {}},
              }

              assert.is_table(log_record.attributes)
              local found_attrs = {}
              for _, attr in ipairs(log_record.attributes) do
                found_attrs[attr.key] = attr.value[attr.value.value]
              end

              local exp_msg_attr = expected_messages_attributes[found_attrs["message.type"]]

              -- filter the right log lines
              if exp_msg_attr then
                -- ensure the log is from the current request
                if found_attrs["request.id"] == request_id then
                  local logline = log_record.body and log_record.body.string_value

                  assert.equals(exp_msg_attr.message, logline)
                  assert.partial_match(exp_msg_attr.attributes, found_attrs)

                  assert.is_string(found_attrs["plugin.id"])
                  assert.is_number(found_attrs["introspection.current.line"])
                  assert.matches("pdk%-logger/handler%.lua", found_attrs["introspection.source"])
                  assert.equals(plugin_name, found_attrs["plugin.name"])
                  assert.equals(plugin_instance_name, found_attrs["plugin.instance.name"])

                  assert.is_number(log_record.time_unix_nano)
                  assert.is_number(log_record.observed_time_unix_nano)

                  found = found + 1
                end
              end
            end
          end
          assert.equals(4, found)
        end

        it("produces and exports valid logs", function()
          local headers, body, request_id

          local cli = helpers.proxy_client()
          local res = assert(cli:send {
            method = "GET",
            path   = "/logs",
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
          assert.logfile().has.no.line("[error]", true)
        end)
      end)

      describe("without OpenTelemetry", function()
        lazy_setup(function()
          bp, _ = assert(helpers.get_db_utils(strategy, {
            "services",
            "routes",
            "plugins",
          }, { "pdk-logger" }))

          local http_srv = assert(bp.services:insert {
            name = "mock-service",
            host = helpers.mock_upstream_host,
            port = helpers.mock_upstream_port,
          })

          local logs_route = assert(bp.routes:insert({
            service = http_srv,
            protocols = { "http" },
            paths = { "/logs" }
          }))

          assert(bp.plugins:insert({
            name = "pdk-logger",
            route = logs_route,
            config = {},
            instance_name = plugin_instance_name,
          }))

          assert(helpers.start_kong({
            database = strategy,
            nginx_conf = "spec/fixtures/custom_nginx.template",
            plugins = "pdk-logger",
          }))
        end)

        lazy_teardown(function()
          helpers.stop_kong()
        end)

        it("handles errors correctly", function()
          local cli = helpers.proxy_client()
          local res = assert(cli:send {
            method = "GET",
            path   = "/logs",
          })
          assert.res_status(200, res)
          cli:close()

          assert.logfile().has.line("Telemetry logging is disabled", true, 10)
        end)
      end)
    end)
  end)
end
