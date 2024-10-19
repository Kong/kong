-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

local debug_spec_helpers = require "spec-ee/02-integration/24-debuggability/helpers"

local TIMEOUT = 10
local TCP_PORT = helpers.get_available_port()

local setup_analytics_sink = debug_spec_helpers.setup_analytics_sink
local assert_dp_logged = debug_spec_helpers.assert_dp_logged
local assert_dp_not_logged = debug_spec_helpers.assert_dp_not_logged
local assert_session_started = debug_spec_helpers.assert_session_started
local teardown_kong = debug_spec_helpers.teardown_kong
local clean_logfiles = debug_spec_helpers.clean_logfiles
local post_updates = debug_spec_helpers.post_updates

local function setup_kong()
  debug_spec_helpers.setup_kong()
  setup_analytics_sink(TCP_PORT)
end


describe("Active Tracing Sampling Behavior", function()
  local proxy_client

  describe("#sampler", function()
    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end
      teardown_kong()
    end)

    lazy_setup(function()
      setup_kong()
      proxy_client = helpers.proxy_client(10000, 9002)
    end)

    before_each(function()
      clean_logfiles()
    end)

    it("records data only when a matching expression is configured", function()
      local available_requests = 3
      local updates_start = {
        sessions = {
          {
            id = "session_id_1",
            action = "START",
            duration = 100,
            sampling_rule = 'http.route == "/sampled"',
            max_samples = available_requests,
          }
        }
      }
      post_updates(proxy_client, updates_start)
      assert_session_started("session_id_1", true, TIMEOUT)

      -- send requests until the sample limit is reached (but NOT exceeded)
      while available_requests > 0 do
        clean_logfiles()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/sampled",
        })
        assert.response(res).has.status(200)
        available_requests = available_requests - 1
        assert_dp_logged("websocket exporter sent \\d+ items", false, TIMEOUT)
      end
      -- confirm the session wasn't stopped yet
      assert_dp_not_logged("sample limit exceeded")

      -- send requests but on a route that does not get sampled
      for _ = 1, 3 do
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/not_sampled",
        })
        assert.response(res).has.status(200)
      end
      -- confirm the session wasn't stopped yet
      assert_dp_not_logged("sample limit exceeded")
      assert_dp_not_logged("disabling instrumentation")

      -- exceed the sample limit by 1 request
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/sampled",
      })
      assert.response(res).has.status(200)
      -- confirm the session was stopped
      assert_dp_logged("sample limit exceeded: ending session", true, TIMEOUT)
      assert_dp_logged("disabling instrumentation", true, TIMEOUT)
    end)
  end)
end)
