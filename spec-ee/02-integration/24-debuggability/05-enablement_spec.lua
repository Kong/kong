-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local debug_spec_helpers = require "spec-ee/02-integration/24-debuggability/helpers"

local assert_dp_not_logged = debug_spec_helpers.assert_dp_not_logged
local teardown_kong = debug_spec_helpers.teardown_kong
local clean_logfiles = debug_spec_helpers.clean_logfiles
local post_updates = debug_spec_helpers.post_updates
local setup_kong = debug_spec_helpers.setup_kong

local proxy_client

describe("#DP enabled active_tracing", function()
  lazy_setup(function()
    setup_kong({}, {
      -- disable it
      active_tracing = "off",
    })
    proxy_client = helpers.proxy_client(10000, 9002)
  end)

  before_each(function()
    clean_logfiles()
  end)


  lazy_teardown(function()
    if proxy_client then
      proxy_client:close()
    end
    teardown_kong()
  end)

  it("does not start a session when active_tracing is disabled", function()
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
    assert_dp_not_logged("session session_id_1 started")
    assert_dp_not_logged("enabling instrumentation")
    local res = proxy_client:send({ method = "GET", path = "/sampled", })
    assert.res_status(200, res)
    assert_dp_not_logged("websocket exporter sent \\d+ items")
  end)
end)
