-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local ws = require "spec-ee.fixtures.websocket"
local cjson = require "cjson"
local assert = require "luassert"
local table_merge = require"kong.tools.table".table_merge

local DP_LOG_FILE = "servroot2/logs/error.log"

local function wait_until_ready()
  assert
    .with_timeout(20)
    .ignore_exceptions(true)
    .eventually(function()
      local proxy_client = helpers.proxy_client(10000, 9002)
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/not_sampled",
      })
      local status = res and res.status
      proxy_client:close()
      return status == 200
    end)
    .is_truthy()
end

local function setup_kong(cp_config, dp_config, db_setup)
  local bp = helpers.get_db_utils("postgres", {
    "clustering_data_planes",
  }, {
    "enable-buffering-response",
    "logger",
  })

  local service = bp.services:insert({
    name = "mock-service",
    url = "http://mock-upstream"
  })

  local route = bp.routes:insert({
    name = "sampled",
    protocols = { "http" },
    paths = { "/sampled" },
    service = { id = service.id },
  })

  bp.routes:insert({
    name = "unbuffered",
    protocols = { "http" },
    paths = { "/unbuffered" },
    service = { id = service.id },
  })

  local upstream = bp.upstreams:insert({
    name = "mock-upstream",
  })

  local target = bp.targets:insert({
    upstream = { id = upstream.id },
    target = helpers.mock_upstream_host .. ":" .. helpers.mock_upstream_port,
  })

  bp.routes:insert({
    service = { id = service.id },
    name = "non_sampled",
    protocols = { "http" },
    paths = { "/not_sampled" },
  })

  local debug_session_route = assert(bp.routes:insert({
    name = "debug-session-manager",
    protocols = { "http" },
    paths = { "/debug-session-update" },
  }))

  if db_setup then
    db_setup(bp)
  end

  bp.plugins:insert({
    name = "pre-function",
    route = { id = debug_session_route.id },
    config = {
      access = {
        [[
          local cjson = require "cjson"
          local updates = kong.request.get_header("updates")
          if updates then
            updates = cjson.decode(updates)
            kong.debug_session:process_updates(updates)
          end
        ]],
      },
    },
  })

  local cp_prefix = helpers.test_conf.prefix

  local env_cp = table_merge({
    role = "control_plane",
    cluster_cert = "spec/fixtures/kong_clustering.crt",
    cluster_cert_key = "spec/fixtures/kong_clustering.key",
    database = "postgres",
    cluster_listen = "127.0.0.1:9005",
    cluster_rpc = "on",
    request_debug = "off",
    log_level = "info",
    nginx_conf = "spec/fixtures/custom_nginx.template",
    prefix = cp_prefix,
  }, cp_config or {})
  assert(helpers.start_kong(env_cp, nil, true))

  local env_dp = (table_merge({
    role = "data_plane",
    database = "off",
    prefix = "servroot2",
    cluster_cert = "spec/fixtures/kong_clustering.crt",
    cluster_cert_key = "spec/fixtures/kong_clustering.key",
    cluster_control_plane = "127.0.0.1:9005",
    cluster_telemetry_endpoint = "0.0.0.0:9123",
    request_debug = "off",
    cluster_rpc = "on",
    log_level = "debug",
    proxy_listen = "0.0.0.0:9002, 0.0.0.0:9443 ssl",
    nginx_conf = "spec/fixtures/custom_nginx.template",
    untrusted_lua = "on",
    konnect_mode = true,
    active_tracing = "on",
  }, dp_config or {}))
  assert(helpers.start_kong(env_dp))
  wait_until_ready()
  return {
    route = route,
    service = service,
    upstream = upstream,
    target = target
  }
end

local function setup_analytics_sink(TCP_PORT)
  local bp = helpers.get_db_utils("postgres", {
    "clustering_data_planes",
  }, { "tcp-ws-trace-exporter" })

  local service = assert(bp.services:insert({
    name  = "ws.test",
    protocol = "ws",
  }))

  assert(bp.routes:insert({
    name  = "ws.test",
    paths = { "/v1/analytics/tracing" },
    protocols = { "ws" },
    service = service,
  }))

  assert(bp.plugins:insert({
    name = "tcp-ws-trace-exporter",
    protocols = { "ws" },
    config = {
      host = "127.0.0.1",
      port = TCP_PORT,
    }
  }))

  -- websocket analytics sink
  assert(helpers.start_kong({
    nginx_conf = "spec/fixtures/custom_nginx.template",
    prefix = "servroot3",
    proxy_listen = "0.0.0.0:9123",
    admin_listen = "0.0.0.0:9124",
    plugins = "bundled,tcp-ws-trace-exporter",
  }, nil, nil, { http_mock = { ws = ws.mock_upstream() } }))
end

local function teardown_analytics_sink(sink_port)
  helpers.stop_kong("servroot3")
  pcall(helpers.kill_tcp_server, sink_port)
end

local function assert_produces_trace(request_func, sink_port, status)
  local thread = helpers.tcp_server(sink_port)
  local res = request_func()
  assert.response(res).has.status(status or 200)

  local ok, s_res = thread:join()
  pcall(helpers.kill_tcp_server, sink_port)
  assert.True(ok)
  local trace = cjson.decode(s_res)
  assert.not_nil(trace)
  return trace
end

local function assert_valid_trace(trace)
  assert.not_nil(trace)

  local resource_spans = trace.resource_spans
  assert.not_nil(resource_spans)
  assert.equal(1, #resource_spans)

  local spans = resource_spans[1].scope_spans[1].spans
  assert.not_nil(spans)
  assert.True(#spans > 0)
end

local function assert_dp_logged(logline, plain, timeout)
  local result
  assert
    .with_timeout(15)
    .ignore_exceptions(true)
    .with_step(1)
    .eventually(function()
      result = assert.logfile(DP_LOG_FILE).has.line(logline, plain, timeout)
      return result
    end)
    .is_truthy()
end

local function assert_dp_not_logged(logline)
  assert.logfile(DP_LOG_FILE).has.no.line(logline)
end

local function assert_session_started(name, plain, timeout)
  plain = plain or true
  timeout = timeout or 10
  assert_dp_logged("debug session " .. name .. " started", plain, timeout)
  assert_dp_logged("enabling sampler", plain, timeout)
end

local function teardown_kong()
  helpers.stop_kong()
  helpers.stop_kong("servroot2")
  helpers.stop_kong("servroot3")
end

local function clean_logfiles()
  helpers.clean_logfile()
  helpers.clean_logfile(DP_LOG_FILE)
  helpers.clean_logfile("servroot3/logs/error.log")
end

local function post_updates(proxy_client, updates)
  local res = proxy_client:send({
    method = "GET",
    path = "/debug-session-update",
    headers = {
      updates = cjson.encode(updates),
    }
  })
  assert.response(res).has.status(200)
end

return {
  setup_kong = setup_kong,
  setup_analytics_sink = setup_analytics_sink,
  teardown_analytics_sink = teardown_analytics_sink,
  assert_valid_trace = assert_valid_trace,
  assert_produces_trace = assert_produces_trace,
  assert_dp_logged = assert_dp_logged,
  assert_dp_not_logged = assert_dp_not_logged,
  assert_session_started = assert_session_started,
  teardown_kong = teardown_kong,
  clean_logfiles = clean_logfiles,
  post_updates = post_updates,
}
