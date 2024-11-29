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
local teardown_analytics_sink = debug_spec_helpers.teardown_analytics_sink
local assert_produces_trace = debug_spec_helpers.assert_produces_trace
local assert_dp_logged = debug_spec_helpers.assert_dp_logged
local assert_session_started = debug_spec_helpers.assert_session_started
local teardown_kong = debug_spec_helpers.teardown_kong
local post_updates = debug_spec_helpers.post_updates
local setup_kong = debug_spec_helpers.setup_kong


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
  --clean_logfiles()
  proxy_client:close()
end


describe("Active Tracing Instrumentation", function()
  describe("#patched functions", function()
    local proxy_client
    lazy_setup(function()
      setup_kong(nil, nil, function(bp)
        local route = bp.routes:insert({
          paths = { "/read_body" },
        })
        bp.plugins:insert({
          name = "pre-function",
          route = {
            id = route.id,
          },
          config = {
            access = {
              [[
                local body_match, err = kong.request.get_header("body_match")
                ngx.req.read_body()
                local body = ngx.req.get_body_data()
                if body ~= body_match then
                  ngx.exit(400)
                end
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

    it("ngx.req.read_body works", function()
      local cjson = require "cjson"
      local body_match = {
        key = "value",
        number = 123,
        array = {1, 2, 3},
        nested =  {
          innerKey = "innerValue"
        }
      }
      local body_match_str = cjson.encode(body_match)
      assert_produces_trace(function()
        return assert(proxy_client:send {
          headers = {
            ["host"] = "localhost",
            ["Content-Type"] = "application/json",
            ["body_match"] = body_match_str,
          },
          method = "POST",
          path = "/read_body",
          body = body_match,
        })
      end, TCP_PORT, 200)
    end)
  end)
end)
