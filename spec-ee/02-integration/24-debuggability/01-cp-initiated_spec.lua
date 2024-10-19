-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local debug_spec_helpers = require "spec-ee/02-integration/24-debuggability/helpers"

local TIMEOUT = 30
local TCP_PORT = helpers.get_available_port()

local setup_analytics_sink = debug_spec_helpers.setup_analytics_sink
local teardown_analytics_sink = debug_spec_helpers.teardown_analytics_sink
local assert_valid_trace = debug_spec_helpers.assert_valid_trace
local assert_produces_trace = debug_spec_helpers.assert_produces_trace
local assert_dp_logged = debug_spec_helpers.assert_dp_logged
local assert_dp_not_logged = debug_spec_helpers.assert_dp_not_logged
local assert_session_started = debug_spec_helpers.assert_session_started
local teardown_kong = debug_spec_helpers.teardown_kong
local clean_logfiles = debug_spec_helpers.clean_logfiles
local post_updates = debug_spec_helpers.post_updates
local setup_kong = debug_spec_helpers.setup_kong

local proxy_client
describe("#CP initiated events", function()
  lazy_setup(function()
    setup_kong()
    proxy_client = helpers.proxy_client(10000, 9002)
  end)

  before_each(function()
    setup_analytics_sink(TCP_PORT)
    clean_logfiles()
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

  it("starts and stops debug sessions", function()
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

    -- verify session started
    assert_session_started("session_id_1", true, TIMEOUT)

    -- verify session delivers data
    local trace = assert_produces_trace(function()
      return assert(proxy_client:send {
        method = "GET",
        path = "/sampled",
      })
    end, TCP_PORT)
    assert_valid_trace(trace)
    assert_dp_logged("websocket exporter sent \\d+ items", false, TIMEOUT)

    clean_logfiles()
    -- stop the debug session
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
    assert_dp_logged("disabling instrumentation", true, TIMEOUT)
    -- verify session does not deliver data
    local res = assert(proxy_client:send {
      method = "GET",
      path = "/sampled",
    })
    assert.response(res).has.status(200)
    assert_dp_not_logged("websocket exporter sent \\d+ items")
  end)

  it("works as expected when stop is followed by start", function()
    local updates_start = {
      sessions = {
        {
          id = "session_id_2",
          action = "START",
          duration = 100,
          max_samples = 100,
        }
      }
    }
    post_updates(proxy_client, updates_start)
    assert_session_started("session_id_2", true, TIMEOUT)

    local updates_stop_start = {
      sessions = {
        {
          id = "session_id_2",
          action = "STOP",
        },
        {
          id = "session_id_3",
          action = "START",
          duration = 100,
          max_samples = 100,
        }
      }
    }
    post_updates(proxy_client, updates_stop_start)
    assert_dp_logged("debug session session_id_2 stopped", true, TIMEOUT)
    assert_session_started("session_id_3", true, TIMEOUT)
    -- verify session delivers data
    local trace = assert_produces_trace(function()
      return assert(proxy_client:send {
        method = "GET",
        path = "/sampled",
      })
    end, TCP_PORT)
    assert_valid_trace(trace)
    assert_dp_logged("websocket exporter sent \\d+ items", false, TIMEOUT)

    local updates_stop = {
      sessions = {
        {
          id = "session_id_3",
          action = "STOP",
        }
      }
    }
    post_updates(proxy_client, updates_stop)
    assert_dp_logged("debug session session_id_3 stopped", true, TIMEOUT)
    assert_dp_logged("disabling instrumentation", true, TIMEOUT)
  end)
end)
