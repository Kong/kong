-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local debug_spec_helpers = require "spec-ee/02-integration/24-debuggability/helpers"
local pb = require "pb"

local TIMEOUT = 10
local TCP_PORT = helpers.get_available_port()

local HTTP_SERVER_PORT_OTEL = helpers.get_available_port()

local setup_analytics_sink = debug_spec_helpers.setup_analytics_sink
local teardown_analytics_sink = debug_spec_helpers.teardown_analytics_sink
local assert_valid_trace = debug_spec_helpers.assert_valid_trace
local assert_produces_trace = debug_spec_helpers.assert_produces_trace
local assert_session_started = debug_spec_helpers.assert_session_started
local teardown_kong = debug_spec_helpers.teardown_kong
local post_updates = debug_spec_helpers.post_updates

local function setup_kong()
  local dp_config = {
    tracing_instrumentations = "request",
    tracing_sampling_rate = 1,
  }

  debug_spec_helpers.setup_kong(nil, dp_config, function(bp)
    assert(bp.plugins:insert {
      name = "opentelemetry",
      config = {
        traces_endpoint = "http://127.0.0.1:" .. HTTP_SERVER_PORT_OTEL,
        batch_flush_delay = 0, -- report immediately
        sampling_rate = 1,
      },
    })
  end)
end


describe("Debuggability: compatibility with OTel tracing tests", function()
  local proxy_client, mock_traces

  lazy_setup(function()
    setup_kong()
    proxy_client = helpers.proxy_client(10000, 9002)
    mock_traces = helpers.http_mock(HTTP_SERVER_PORT_OTEL, { timeout = 20 })
  end)

  before_each(function()
    setup_analytics_sink(TCP_PORT)
  end)

  after_each(function()
    teardown_analytics_sink(TCP_PORT)
  end)

  lazy_teardown(function()
    if proxy_client then
      proxy_client:close()
    end
    teardown_kong()
    if mock_traces then
      mock_traces("close", true)
    end
  end)

  it("does not report \"debug\" spans via OTel", function()
    -- start a debug session
    local updates_start = {
      sessions = {
        {
          id = "session_id_1",
          action = "START",
          duration = 100,
          max_samples = 100,
        }
      }
    }
    post_updates(proxy_client, updates_start)

    -- the first timer run should pick up the session start event
    -- and start the first debug session
    assert_session_started("session_id_1", true, TIMEOUT)
    -- verify debug traces are delivered successfully
    local trace = assert_produces_trace(function()
      return assert(proxy_client:send {
        method = "GET",
        path = "/sampled",
      })
    end, TCP_PORT)
    assert_valid_trace(trace)

    -- wait for otel traces to be delivered as well
    local body
    assert
        .eventually(function()
          local lines
          lines, body = mock_traces()
          return lines
        end)
        .is_truthy()

    assert.is_string(body)
    local decoded = assert(pb.decode("opentelemetry.proto.collector.trace.v1.ExportTraceServiceRequest", body))
    assert.not_nil(decoded)
    local resource_span = assert(decoded.resource_spans[1])
    local scope_spans = assert(resource_span.scope_spans)
    local spans = assert(scope_spans[1].spans)
    -- only the configured spans ("request") must be reported, and not the
    -- "debug" spans that were produced only for the debug session
    assert.equals(1, #spans)
    local request_span = spans[1]
    assert.equals("kong", request_span.name)
  end)
end)
