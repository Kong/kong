-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local helpers = require "spec.helpers"
local pretty = require "pl.pretty"
local debug_spec_helpers = require "spec-ee/02-integration/24-debuggability/helpers"

local TIMEOUT = 10
local TCP_PORT = helpers.get_available_port()

local setup_analytics_sink = debug_spec_helpers.setup_analytics_sink
local teardown_analytics_sink = debug_spec_helpers.teardown_analytics_sink
local assert_valid_trace = debug_spec_helpers.assert_valid_trace
local assert_produces_trace = debug_spec_helpers.assert_produces_trace
local assert_dp_logged = debug_spec_helpers.assert_dp_logged
local assert_session_started = debug_spec_helpers.assert_session_started
local teardown_kong = debug_spec_helpers.teardown_kong
local post_updates = debug_spec_helpers.post_updates
local setup_kong = debug_spec_helpers.setup_kong
local clean_logfiles = debug_spec_helpers.clean_logfiles

local fmt = string.format


local uuid_pattern = "^" .. ("%x"):rep(8)  .. "%-" .. ("%x"):rep(4) .. "%-"
                         .. ("%x"):rep(4)  .. "%-" .. ("%x"):rep(4) .. "%-"
                         .. ("%x"):rep(12) .. "$"
local hex_128_pattern = "^" .. ("%x"):rep(32) .. "$"
local number_pattern = "%d+"
local host_pattern = "%d+%.%d+%.%d+%.%d+"
local host_and_port_pattern = host_pattern .. ":" .. number_pattern

local function SPAN_ATTRIBUTES(entities, opts)
  local route_id = entities and entities.route and entities.route.id or "unknown"
  local service_id = entities and entities.route and entities.route.service.id or "unknown"
  local upstream_id = entities and entities.upstream and entities.upstream.id or "unknown"
  local target_id = entities and entities.target and entities.target.id or "unknown"
  local lb_algorithm = entities and entities.upstream and "round-robin" or "unknown"

  local path = opts and opts.path or "/sampled"
  local method = opts and opts.method or "GET"

  return {
    ["kong"] = {
      ["proxy.kong.request.id"] = { assertion = "matches", expected_val = hex_128_pattern},
      ["network.protocol.version"] = { assertion = "equals", expected_val = "1.1"},
      ["proxy.kong.upstream.read_response_duration_ms"] = { assertion = "matches", expected_val = number_pattern},
      ["url.scheme"] = { assertion = "matches", expected_val = "http[s]?"},
      ["proxy.kong.latency_total_ms"] = { assertion = "matches", expected_val = number_pattern},
      ["proxy.kong.redis.total_io_ms"] = { assertion = "matches", expected_val = number_pattern},
      ["proxy.kong.tcpsock.total_io_ms"] = { assertion = "matches", expected_val = number_pattern},
      ["url.full"] = { assertion = "matches", expected_val = "http[s]?://localhost" .. path},
      ["http.request.header.host"] = { assertion = "equals", expected_val = "localhost"},
      ["http.response.status_code"] = { assertion = "equals", expected_val = 200},
      ["network.peer.address"] = { assertion = "equals", expected_val = "127.0.0.1"},
      ["proxy.kong.service.id"] = { assertion = "equals", expected_val = service_id},
      ["proxy.kong.route.id"] = { assertion = "equals", expected_val = route_id},
      ["proxy.kong.upstream.id"] = { assertion = "equals", expected_val = upstream_id},
      ["proxy.kong.target.id"] = { assertion = "equals", expected_val = target_id},
      ["proxy.kong.upstream.addr"] = { assertion = "equals", expected_val = "127.0.0.1"},
      ["proxy.kong.upstream.host"] = { assertion = "matches", expected_val = host_and_port_pattern},
      ["proxy.kong.upstream.ttfb_ms"] = { assertion = "matches", expected_val = number_pattern},
      ["client.address"] = { assertion = "equals", expected_val = "127.0.0.1"},
      ["http.route"] = { assertion = "equals", expected_val = path},
      ["http.request.method"] = { assertion = "equals", expected_val = method},
    },
    ["kong.upstream.try_select"] = {
      ["try_count"] = { assertion = "matches", expected_val = number_pattern},
      ["network.peer.address"] = { assertion = "equals", expected_val = "127.0.0.1"},
      ["network.peer.port"] = { assertion = "matches", expected_val = number_pattern},
      ["network.peer.name"] = { assertion = "equals", expected_val = "127.0.0.1"},
      ["keepalive"] = { assertion = "equals", expected_val = true},
      ["proxy.kong.target.id"] = { assertion = "equals", expected_val = target_id},
      ["proxy.kong.upstream.connect_duration_ms"] = { assertion = "matches", expected_val = number_pattern},
    },
    ["kong.io.http.request"] = {
      ["http.url"] = { assertion = "equals", expected_val = "httpbin.konghq.com"},
      ["http.method"] = { assertion = "equals", expected_val = "GET"},
      ["http.flavor"] = { assertion = "matches", expected_val = "%d.*"},
      ["http.user_agent"] = { assertion = "matches", expected_val = ".*"},
    },
    ["kong.upstream.selection"] = {
      ["proxy.kong.upstream.lb_algorithm"] = { assertion = "equals", expected_val = lb_algorithm},
      ["proxy.kong.upstream.id"] = { assertion = "equals", expected_val = upstream_id},
      ["try_count"] = { assertion = "matches", expected_val = number_pattern},
    },
    ["kong.dns"] = {
      ["proxy.kong.dns.record.domain"] = { assertion = "matches", expected_val = "localhost"},
      ["proxy.kong.dns.record.ip"] = { assertion = "matches", expected_val = "%d+%.%d+%.%d+%.%d+"},
      ["proxy.kong.dns.record.port"] = { assertion = "matches", expected_val = number_pattern},
    },
    ["kong.read_client_http_headers"] = {
      ["raw_header_size_total"] = { assertion = "matches", expected_val = number_pattern},
      ["raw_header_count"] = { assertion = "matches", expected_val = number_pattern},
    },
    ["kong.access.plugin.enable-buffering-response"] = {
      ["proxy.kong.plugin.id"] = { assertion = "matches", expected_val = uuid_pattern},
    },
    ["kong.response.plugin.enable-buffering-response"] = {
      ["proxy.kong.plugin.id"] = { assertion = "matches", expected_val = uuid_pattern},
    },
    ["kong.certificate.plugin.logger"] = {
      ["proxy.kong.plugin.id"] = { assertion = "matches", expected_val = uuid_pattern},
    },
    ["kong.rewrite.plugin.logger"] = {
      ["proxy.kong.plugin.id"] = { assertion = "matches", expected_val = uuid_pattern},
    },
    ["kong.access.plugin.logger"] = {
      ["proxy.kong.plugin.id"] = { assertion = "matches", expected_val = uuid_pattern},
    },
    ["kong.header_filter.plugin.logger"] = {
      ["proxy.kong.plugin.id"] = { assertion = "matches", expected_val = uuid_pattern},
    },
    ["kong.body_filter.plugin.logger"] = {
      ["proxy.kong.plugin.id"] = { assertion = "matches", expected_val = uuid_pattern},
    },
    ["kong.debug_session.sample"] = {
      ["proxy.kong.sampling_rule"] = { assertion = "equals", expected_val = "http.route == \"/sampled\""},
    },
    ["kong.phase.certificate"] = {},
    ["kong.phase.rewrite"] = {},
    ["kong.phase.access"] = {},
    ["kong.phase.header_filter"] = {},
    ["kong.phase.body_filter"] = {},
    ["kong.phase.response"] = {},
    ["kong.read_client_http_body"] = {},
    ["kong.router"] = {},
    ["kong.upstream.ttfb"] = {},
    ["kong.upstream.read_response"] = {},
    ["kong.io.socket.send"] = {},
    ["kong.io.socket.receive"] = {},
    ["kong.io.redis"] = {},
  }
end

local function get_attribute_value(span, attribute)
  for _, span_attr in ipairs(span.attributes) do
    if span_attr.key == attribute then
      return span_attr.value[span_attr.value.value]
    end
  end
end

local function get_spans(name, spans)
  local res = {}
  for _, span in ipairs(spans) do
    if span.name == name then
      res[#res + 1] = span
    end
  end
  return #res > 0 and res or nil
end

local function assert_get_spans(name, spans, count)
  local res = get_spans(name, spans)
  assert.is_truthy(res, fmt("\nExpected to find %q span in:\n%s\n",
    name, pretty.write(spans)))
  if count then
    assert.equals(count, #res, fmt("\nExpected to find %d %q spans in:\n%s\n",
      count, name, pretty.write(spans)))
  end
  return #res == 1 and res[1] or res
end

local function assert_parent_child_relationship(parent_span, child_span)
  assert.True(parent_span.span_id == child_span.parent_span_id,
      fmt("\nExpected %s to be child of %s\n", child_span.name, parent_span.name))

  -- due to loss of precision during unit conversions and the fact some timings
  -- come from different sources, we accept a 3ms tolerance - for some reason
  -- this appears to be more of a problem in CI.
  -- TODO: try to improve this precision and get the tolerance down to <= 1ms
  local tolerance = 3e6
  assert.True(parent_span.start_time_unix_nano > 0,
      fmt("\nExpected %s to have a start time\n", parent_span.name))
  assert.True(child_span.start_time_unix_nano > 0,
      fmt("\nExpected %s to have a start time\n", child_span.name))
  assert.True(parent_span.end_time_unix_nano > 0,
      fmt("\nExpected %s to have an end time\n", parent_span.name))
  assert.True(child_span.end_time_unix_nano > 0,
      fmt("\nExpected %s to have an end time\n", child_span.name))

  local offset = parent_span.start_time_unix_nano - child_span.start_time_unix_nano
  assert.True(offset <= tolerance,
      fmt("\nExpected %s to start before %s but it started %dms after\n",
      parent_span.name, child_span.name, offset / 1e6))
  offset = child_span.end_time_unix_nano - parent_span.end_time_unix_nano
  assert.True(offset <= tolerance,
      fmt("\nExpected %s to end before %s but it ended %dms after\n",
      child_span.name, parent_span.name, offset / 1e6))
end

-- asserts that the trace contains the expected spans and that they are in the right order
-- @tparam table  spans the trace's spans
-- @tparam bool   ssl whether the request was made over SSL (certificate phase executed)
-- @tparam bool   buffering whether proxy buffering mode is enabled
-- @tparam string plugin_name name of a plugin that executes all phases
local function assert_has_default_spans(spans, ssl, buffering, plugin_name)
  local root_span = assert_get_spans("kong", spans, 1)
  local phase_rewrite_span = assert_get_spans("kong.phase.rewrite", spans, 1)
  local phase_access_span = assert_get_spans("kong.phase.access", spans, 1)
  local phase_header_filter_span = assert_get_spans("kong.phase.header_filter", spans, 1)
  local phase_body_filter_span = assert_get_spans("kong.phase.body_filter", spans, 1)
  local read_headers_span = assert_get_spans("kong.read_client_http_headers", spans, 1)
  local router_span = assert_get_spans("kong.router", spans, 1)
  local upstream_selection_span = assert_get_spans("kong.upstream.selection", spans, 1)
  local upstream_try_span = assert_get_spans("kong.upstream.try_select", spans, 1)
  local upstream_ttfb_span = assert_get_spans("kong.upstream.ttfb", spans, 1)
  local upstream_read_response_span = assert_get_spans("kong.upstream.read_response", spans, 1)

  assert_parent_child_relationship(root_span, phase_rewrite_span)
  assert_parent_child_relationship(root_span, phase_access_span)
  assert_parent_child_relationship(root_span, read_headers_span)
  assert_parent_child_relationship(phase_access_span, router_span)
  assert_parent_child_relationship(root_span, upstream_selection_span)
  assert_parent_child_relationship(upstream_selection_span, upstream_try_span)
  assert_parent_child_relationship(root_span, upstream_ttfb_span)
  assert_parent_child_relationship(root_span, upstream_read_response_span)

  if ssl then
    local phase_certificate_span = assert_get_spans("kong.phase.certificate", spans, 1)
    assert_parent_child_relationship(root_span, phase_certificate_span)

    if plugin_name then
      local plugin_certificate_span = assert_get_spans("kong.certificate.plugin." .. plugin_name, spans, 1)
      local plugin_rewrite_span = assert_get_spans("kong.rewrite.plugin." .. plugin_name, spans, 1)
      local plugin_access_span = assert_get_spans("kong.access.plugin." .. plugin_name, spans, 1)
      local plugin_header_filter_span = assert_get_spans("kong.header_filter.plugin." .. plugin_name, spans, 1)
      local plugin_body_filter_span = assert_get_spans("kong.body_filter.plugin." .. plugin_name, spans, 1)

      assert_parent_child_relationship(phase_certificate_span, plugin_certificate_span)
      assert_parent_child_relationship(phase_rewrite_span, plugin_rewrite_span)
      assert_parent_child_relationship(phase_access_span, plugin_access_span)
      assert_parent_child_relationship(phase_header_filter_span, plugin_header_filter_span)
      assert_parent_child_relationship(phase_body_filter_span, plugin_body_filter_span)
    end
  end

  if buffering then
    local phase_response_span = assert_get_spans("kong.phase.response", spans, 1)
    assert_parent_child_relationship(root_span, phase_response_span)
    assert_parent_child_relationship(phase_response_span, phase_header_filter_span)
    assert_parent_child_relationship(phase_response_span, phase_body_filter_span)

    local response_plugin_span = assert_get_spans("kong.response.plugin.enable-buffering-response", spans, 1)
    assert_parent_child_relationship(phase_response_span, response_plugin_span)
  else
    assert_parent_child_relationship(root_span, phase_header_filter_span)
    assert_parent_child_relationship(root_span, phase_body_filter_span)
  end
end

local function assert_valid_attributes(span, attributes)
  for attr_name, expected in pairs(attributes) do
    local assertion = expected.assertion
    local expected_val = expected.expected_val
    local attr_val = get_attribute_value(span, attr_name)
    assert(attr_val, fmt("\nExpected span %s to have attribute %s, but got %s\n",
        span.name, attr_name, pretty.write(span.attributes)))

    assert[assertion](expected_val, attr_val, fmt(
      "Expected span %s to have attribute %s with value %s %s, but got %s\n",
      span.name, attr_name, assertion, expected_val, attr_val))
  end
end

local function assert_spans_have_valid_attributes(spans, entities, opts)
  for _, span in ipairs(spans) do
    local expected_attributes = SPAN_ATTRIBUTES(entities, opts)[span.name]
    if expected_attributes then
      assert_valid_attributes(span, expected_attributes)
    end
  end
end

local function start_session()
  local proxy_client = helpers.proxy_client(10000, 9002)
  setup_analytics_sink(TCP_PORT)
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
  -- verify session started
  assert_session_started("session_id_1", true, TIMEOUT)
  proxy_client:close()
end

local function stop_session()
  local proxy_client = helpers.proxy_client(10000, 9002)
  local updates_stop = {
    sessions = {
      {
        id = "session_id_1",
        action = "STOP",
      }
    }
  }
  post_updates(proxy_client, updates_stop)
  -- verify session stopped
  assert_dp_logged("debug session session_id_1 stopped", true, TIMEOUT)
  clean_logfiles()
  proxy_client:close()
end


describe("Active Tracing Instrumentation", function()
  describe("#normal conditions", function()
    local proxy_client, entities

    lazy_setup(function()
      entities = setup_kong()
      proxy_client = helpers.proxy_client(10000, 9002)
    end)

    after_each(function()
      teardown_analytics_sink(TCP_PORT)
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end
      teardown_kong()
    end)

    before_each(start_session)
    after_each(stop_session)

    it("produces the expected spans and attributes", function()
      local trace = assert_produces_trace(function()
        return assert(proxy_client:send {
          headers = {
            ["host"] = "localhost",
          },
          method = "GET",
          path = "/sampled",
        })
      end, TCP_PORT)

      assert_valid_trace(trace)

      local spans = trace.resource_spans[1].scope_spans[1].spans
      assert.True(spans and #spans > 0)
      assert_has_default_spans(spans)

      -- spans contain expected attributes
      local opts = {
        path = "/sampled",
        method = "GET",
      }
      assert_spans_have_valid_attributes(spans, entities, opts)
    end)
  end)

  describe("#buffering enabled", function()
    local proxy_client, entities
    lazy_setup(function()
      entities = setup_kong({
        plugins = "bundled,enable-buffering-response",
      }, {
        plugins = "bundled,enable-buffering-response",
      }, function(bp)
        bp.plugins:insert({
          name = "enable-buffering-response",
        })
      end)
      proxy_client = helpers.proxy_client(10000, 9002)
    end)

    after_each(function()
      teardown_analytics_sink(TCP_PORT)
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end
      teardown_kong()
    end)

    before_each(start_session)
    after_each(stop_session)

    it("produces the expected spans and attributes", function()
      local trace = assert_produces_trace(function()
        return assert(proxy_client:send {
          headers = {
            ["host"] = "localhost",
          },
          method = "GET",
          path = "/sampled",
        })
      end, TCP_PORT)

      assert_valid_trace(trace)

      local spans = trace.resource_spans[1].scope_spans[1].spans
      assert.True(spans and #spans > 0)
      assert_has_default_spans(spans, nil, true)

      -- spans contain expected attributes
      local opts = {
        path = "/sampled",
        method = "GET",
      }
      assert_spans_have_valid_attributes(spans, entities, opts)
    end)
  end)

  describe("#plugin spans", function()
    local proxy_client, entities
    lazy_setup(function()
      entities = setup_kong({
        plugins = "bundled,logger",
      }, {
        plugins = "bundled,logger",
      }, function(bp)
        bp.plugins:insert({
          name = "logger",
        })
      end)
      proxy_client = helpers.proxy_client(10000, 9002)
    end)

    after_each(function()
      teardown_analytics_sink(TCP_PORT)
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end
      teardown_kong()
    end)

    before_each(start_session)
    after_each(stop_session)

    it("produces the expected spans and attributes", function()
      local proxy_ssl_client = helpers.proxy_ssl_client()
      finally(function()
        proxy_ssl_client:close()
      end)

      local trace = assert_produces_trace(function()
        return assert(proxy_ssl_client:send {
          headers = {
            ["host"] = "localhost",
          },
          method = "GET",
          path = "/sampled",
        })
      end, TCP_PORT)

      assert_valid_trace(trace)

      local spans = trace.resource_spans[1].scope_spans[1].spans
      assert.True(spans and #spans > 0)
      assert_has_default_spans(spans, true, false, "logger")

      -- spans contain expected attributes
      local opts = {
        path = "/sampled",
        method = "GET",
      }
      assert_spans_have_valid_attributes(spans, entities, opts)
    end)
  end)

  describe("#kong.read_client_http_body span", function()
    local proxy_client, entities, plugin_route
    lazy_setup(function()
      entities = setup_kong(nil, nil, function(bp)
        plugin_route = bp.routes:insert({
          paths = { "/read_body" }
        })
        bp.plugins:insert({
          name = "request-transformer",
          route = { id = plugin_route.id },
          config = {
            add = {
              body = { "body:somecontent" }
            },
          }
        })
      end)
      proxy_client = helpers.proxy_client(10000, 9002)
    end)

    after_each(function()
      teardown_analytics_sink(TCP_PORT)
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end
      teardown_kong()
    end)

    before_each(start_session)
    after_each(stop_session)

    describe("when a plugin reads the body", function()
      it("is child of the plugin's span", function()
        local trace = assert_produces_trace(function()
          return assert(proxy_client:send {
            method = "POST",
            path = "/read_body",
            body = { "hello: world" },
            headers = {
              ["Content-Type"] = "application/json",
              ["host"] = "localhost"
            },
          })
        end, TCP_PORT)

        assert_valid_trace(trace)

        local spans = trace.resource_spans[1].scope_spans[1].spans
        assert.True(spans and #spans > 0)
        assert_has_default_spans(spans)
        -- we expect 2: one from get_raw_body, one from set_raw_body
        local read_body_spans = assert_get_spans("kong.read_client_http_body", spans, 2)
        assert.not_nil(read_body_spans)
        assert.equals(2, #read_body_spans)
        local plugin_span = assert_get_spans("kong.access.plugin.request-transformer", spans, 1)

        -- verify that the read body spans are children of the plugin span
        assert_parent_child_relationship(plugin_span, read_body_spans[1])
        assert_parent_child_relationship(plugin_span, read_body_spans[2])
        local opts = {
          path = "/read_body",
          method = "POST",
        }
        assert_spans_have_valid_attributes(spans, {
          route = plugin_route
        }, opts)
      end)
    end)

    describe("when NO plugin reads the body", function()
      it("is child of the root span", function()
        local trace = assert_produces_trace(function()
          return assert(proxy_client:send {
            method = "POST",
            path = "/sampled",
            body = { "hello: world" },
            headers = {
              ["Content-Type"] = "application/json",
              ["host"] = "localhost"
            },
          })
        end, TCP_PORT)

        assert_valid_trace(trace)

        local spans = trace.resource_spans[1].scope_spans[1].spans
        assert.True(spans and #spans > 0)
        assert_has_default_spans(spans)

        local read_body_span = assert_get_spans("kong.read_client_http_body", spans, 1)
        local root_span = assert_get_spans("kong", spans, 1)

        -- verify that the read body span is child of the root span
        assert_parent_child_relationship(root_span, read_body_span)
        local opts = {
          path = "/sampled",
          method = "POST",
        }
        assert_spans_have_valid_attributes(spans, entities, opts)
      end)
    end)
  end)

  describe("#IO spans", function()
    local proxy_client, entities
    lazy_setup(function()
      entities = setup_kong(nil, nil, function(bp)
        bp.plugins:insert({
          name = "pre-function",
          config = {
            access = {
              [[
                local http = require("resty.http")
                local httpc = http.new()
                local res, err = httpc:request_uri("httpbin.konghq.com", {
                  method = "GET",
                  path = "/anything",
                })
                
                local tcp_sock = ngx.socket.tcp()

                tcp_sock:connect("localhost", 4242)
                local bytes, err = tcp_sock:send("\n foo")
                if bytes then
                  local ok, err = tcp_sock:setkeepalive()
                  if not ok then
                    tcp_sock:close()
                  end
                end
                tcp_sock:receive("*a")

                local redis = require "kong.enterprise_edition.tools.redis.v2"
                local red = redis.connection({
                  host = "localhost",
                  port = 6379,
                })
                red:set("foo", "bar")
              ]]
            }
          }
        })
      end)
      proxy_client = helpers.proxy_client(10000, 9002)
    end)

    after_each(function()
      teardown_analytics_sink(TCP_PORT)
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end
      teardown_kong()
    end)

    before_each(start_session)
    after_each(stop_session)

    it("produces the expected spans and attributes", function()
      local trace = assert_produces_trace(function()
        return assert(proxy_client:send {
          headers = {
            ["host"] = "localhost",
          },
          method = "GET",
          path = "/sampled",
        })
      end, TCP_PORT)

      assert_valid_trace(trace)

      local spans = trace.resource_spans[1].scope_spans[1].spans
      assert.True(spans and #spans > 0)
      assert_has_default_spans(spans)

      assert_get_spans("kong.io.http.request", spans, 1)
      assert_get_spans("kong.dns", spans)

      assert_get_spans("kong.io.socket.send", spans)
      assert_get_spans("kong.io.socket.connect", spans)
      assert_get_spans("kong.io.socket.receive", spans)
      assert_get_spans("kong.io.redis", spans)

      -- spans contain expected attributes
      local opts = {
        path = "/sampled",
        method = "GET",
      }
      assert_spans_have_valid_attributes(spans, entities, opts)
    end)
  end)

  describe("#short-circuits", function()
    local proxy_client

    lazy_setup(function()
      setup_kong(nil, nil, function(bp)
        bp.routes:insert({
          paths = { "/short_circuited" },
          protocols = { "https" },
        })
      end)
      proxy_client = helpers.proxy_client(10000, 9002)
    end)

    after_each(function()
      teardown_analytics_sink(TCP_PORT)
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end
      teardown_kong()
    end)

    before_each(start_session)
    after_each(stop_session)

    it("produces correct access phase span when short-circuited during access", function()
      local trace = assert_produces_trace(function()
        return assert(proxy_client:send {
          headers = {
            ["host"] = "localhost",
          },
          method = "GET",
          path = "/short_circuited",
        })
      end, TCP_PORT, 426)

      assert_valid_trace(trace)

      local spans = trace.resource_spans[1].scope_spans[1].spans
      assert.True(spans and #spans > 0)

      local root_span = assert_get_spans("kong", spans, 1)
      local access_phase_span = assert_get_spans("kong.phase.access", spans, 1)
      assert_parent_child_relationship(root_span, access_phase_span)
    end)
  end)
end)
