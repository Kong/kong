-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

local debug_spec_helpers = require "spec-ee/02-integration/24-debuggability/helpers"

local fmt = string.format

local assert_dp_logged = debug_spec_helpers.assert_dp_logged
local teardown_kong = debug_spec_helpers.teardown_kong
local clean_logfiles = debug_spec_helpers.clean_logfiles
local post_updates = debug_spec_helpers.post_updates
local assert_session_started = debug_spec_helpers.assert_session_started


describe("Active Tracing Sampling in/out", function()
  local proxy_client, route_id, service_id, upstream_id

  describe("#sampler ", function()
    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end
      teardown_kong()
    end)

    lazy_setup(function()
      local entities = debug_spec_helpers.setup_kong()
      route_id = entities and entities.route and entities.route.id
      service_id = entities and entities.route and entities.route.service.id
      upstream_id = entities and entities.upstream and entities.upstream.id
      proxy_client = helpers.proxy_client(10000, 9002)
    end)

    after_each(function()
      clean_logfiles()
    end)

    local session_id = 1
    local function test_sampling_rule(sampling_rule, assertion)
      assertion = assertion == nil and true or assertion
      local available_requests = 10
      session_id = session_id + 1
      local duration = 10
      local updates_start = {
        sessions = {
          {
            id = tostring(session_id),
            action = "START",
            duration = duration,
            sampling_rule = sampling_rule,
            max_samples = available_requests,
          }
        }
      }
      post_updates(proxy_client, updates_start)
      assert_session_started(session_id, true, 10)
      assert_dp_logged("enabling instrumentation")
      assert_dp_logged("enabling sampler")
      assert_dp_logged("adding matcher with expression: " .. sampling_rule)

      for _ = 1, available_requests + 1 do
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/sampled",
          headers = {
            ["host"] = "example.com",
            ["x-another-header"] = "that-increases-header-size"
          },
        })
        assert.response(res).has.status(200)
        local assertion_line = (fmt("sampler returned: %s", assertion))
        assert_dp_logged(assertion_line)
      end
      if assertion then
        -- we only disable the sampler when the last request was sampled
        -- in _this_ test. We have tests that verify that sessions end
        -- correctly after the defined time-period
        assert_dp_logged("disabling sampler")
      end
      return true
    end

    describe("#collects ", function()
      it("#http.route", function()
        assert(test_sampling_rule('http.route == "/sampled"'))
      end)

      it("#http.route alias -> http.path", function()
        assert(test_sampling_rule('http.path== "/sampled"'))
      end)

      it("#http.request.method", function()
        assert(test_sampling_rule('http.request.method == "GET"'))
      end)

      it("#client.address", function()
        assert(test_sampling_rule('client.address == 127.0.0.1'))
      end)

      it("#client.port", function()
        assert(test_sampling_rule('client.port >= 1'))
      end)

      it("#client.address alias -> net.src.ip", function()
        assert(test_sampling_rule('net.src.ip == 127.0.0.1'))
      end)

      it("#http.response.status_code", function()
        assert(test_sampling_rule('http.response.status_code == 200'))
      end)

      it("#proxy.kong.latency.total", function()
        assert(test_sampling_rule('proxy.kong.latency.total <= 10000'))
      end)

      it("#kong.proxy.route.id", function()
        assert(test_sampling_rule(fmt('proxy.kong.route.id == "%s"', route_id)))
      end)

      it("#kong.proxy.service.id", function()
        assert(test_sampling_rule(fmt('proxy.kong.service.id == "%s"', service_id)))
      end)

      it("#proxy.kong.tcpsock.total_io", function()
        assert(test_sampling_rule('proxy.kong.latency.3p.tcpsock.total_io <= 10000'))
      end)

      it("#proxy.kong.redis.total_io", function()
        assert(test_sampling_rule('proxy.kong.latency.3p.redis.total_io <= 10000'))
      end)

      it("#network.peer.address", function ()
        assert(test_sampling_rule('network.peer.address == 127.0.0.1'))
      end)

      it("#network.peer.port", function ()
        assert(test_sampling_rule('network.peer.port >= 1'))
      end)

      it("#network.protocol.name", function ()
        assert(test_sampling_rule('network.protocol.name == "http"'))
      end)

      it("#url.full", function ()
        assert(test_sampling_rule('url.full == "http://example.com/sampled"'))
      end)

      it("#url.scheme", function ()
        assert(test_sampling_rule('url.scheme == "http"'))
      end)

      it("#proxy.kong.latency.upstream.ttfb", function ()
        assert(test_sampling_rule('proxy.kong.latency.upstream.ttfb <= 10'))
      end)

      -- TODO: this seems not quite right. Review
      pending("#proxy.kong.upstream.addr", function()
        assert(test_sampling_rule('proxy.kong.upstream.addr == "127.0.0.1"'))
      end)

      -- TODO: this seems not quite right. Review
      pending("#proxy.kong.upstream.host", function()
        assert(test_sampling_rule('proxy.kong.upstream.host == "127.0.0.1: 15555"'))
      end)

      it("#http.host", function ()
        assert(test_sampling_rule('http.host == "example.com"'))
      end)

      it("#http.host alias -> http.request.header.host", function ()
        assert(test_sampling_rule('http.request.header.host == "example.com"'))
      end)

      it("#read_response_duration", function ()
        assert(test_sampling_rule('proxy.kong.latency.upstream.read_response_duration <= 10000'))
      end)

      it("#proxy.kong.upstream.id", function()
        assert(test_sampling_rule(fmt('proxy.kong.upstream.id == "%s"', upstream_id)))
      end)

      it("#http.request.size", function()
        assert(test_sampling_rule('http.request.size >= 1'))
      end)

    end)


    describe("#drops ", function()
      it("#http.route NEG", function()
        assert(test_sampling_rule('http.route == "/certainly-not-sampled"', false))
      end)

      it("#http.route alias -> http.path NEG", function()
        assert(test_sampling_rule('http.path== "/certainly-not-sampled"', false))
      end)

      it("#http.response.status_code NEG", function()
        -- certainly not a teapot
        assert(test_sampling_rule('http.response.status_code == 418', false))
      end)

      it("#http.request.method NEG", function()
        assert(test_sampling_rule('http.request.method == "POST"', false))
      end)

      it("#client.address NEG", function()
        assert(test_sampling_rule('client.address == 192.168.0.1', false))
      end)

      it("#client.address alias -> net.src.ip NEG", function()
        assert(test_sampling_rule('net.src.ip == 192.168.0.1', false))
      end)

      it("#client.port NEG", function()
        assert(test_sampling_rule('client.port <= 1', false))
      end)

      it("#proxy.kong.latency.totals NEG", function()
        assert(test_sampling_rule('proxy.kong.latency.total < 0', false))
      end)

      it("#route.id NEG", function()
        assert(test_sampling_rule(fmt('proxy.kong.route.id == "non-matching"'), false))
      end)

      it("#service.id NEG", function()
        assert(test_sampling_rule(fmt('proxy.kong.service.id == "non-matching"'), false))
      end)

      it("#proxy.kong.tcpsock.total_io NEG", function()
        assert(test_sampling_rule('proxy.kong.latency.tcpsock.total_io < 0', false))
      end)

      it("#proxy.kong.redis.total_io NEG", function()
        assert(test_sampling_rule('proxy.kong.latency.redis.total_io < 0', false))
      end)

      it("#network.peer.address NEG", function()
        assert(test_sampling_rule('network.peer.address == "192.168.0.1"', false))
      end)

      it("#network.peer.port NEG", function ()
        assert(test_sampling_rule('network.peer.port <= 1', false))
      end)

      it("#network.protocol.name NEG", function ()
        assert(test_sampling_rule('network.protocol.name == "grpc"', false))
      end)

      it("#url.full NEG", function()
        assert(test_sampling_rule('url.full == "https://certainly-not-example.com/not-sampled"', false))
      end)

      it("#url.scheme NEG", function()
        assert(test_sampling_rule('url.scheme == "https"', false))
      end)

      it("#proxy.kong.lantency.upstream.ttfb NEG", function()
        assert(test_sampling_rule('proxy.kong.latency.upstream.ttfb < 0', false))
      end)

      it("#proxy.kong.upstream.addr NEG", function()
        assert(test_sampling_rule('proxy.kong.upstream.addr == "192.168.0.1"', false))
      end)

      it("#proxy.kong.upstream.host NEG", function()
        assert(test_sampling_rule('proxy.kong.upstream.host == "example.com:8080"', false))
      end)

      it("#http.host NEG", function()
        assert(test_sampling_rule('http.host == "certainly-not-example.com"', false))
      end)

      it("#http.host alias -> http.request.header.host NEG", function()
        assert(test_sampling_rule('http.request.header.host == "certainly-not-example.com"', false))
      end)

      it("#proxy.kong.upstream.read_response_duration NEG", function()
        assert(test_sampling_rule('proxy.kong.latency.upstream.read_response_duration < 0', false))
      end)

      it("#proxy.kong.upstream.id NEG", function()
        assert(test_sampling_rule('proxy.kong.upstream.id == "non-existent-id"', false))
      end)

      it("#http.request.size NEG", function()
        assert(test_sampling_rule('http.request.size <= 0', false))
      end)
    end)

  end)
end)
