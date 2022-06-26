-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local strategies = require "kong.tracing.strategies"

describe(".flush", function()
  local tracing = require "kong.tracing"
  local native_ngx_get_phase = ngx.get_phase

  setup(function()
    tracing.init({
      tracing = true,
      tracing_types = { "all" },
      tracing_time_threshold = 0,
      tracing_write_strategy = "mock",
      tracing_write_endpoint = "mock_endpoint",
    })

    ngx.get_phase = function() return "foo" end -- luacheck: ignore
  end)

  teardown(function ()
    ngx.get_phase = native_ngx_get_phase -- luacheck: ignore
  end)

  it("flushes traces via configured write strategy/endpoint", function()
    strategies.flushers = {
      mock = function(traces, endpoint) end
    }

    mock(strategies.flushers)

    local trace = tracing.trace("foo")
    assert.same("foo", trace.name)
    trace:finish()

    local runs_old = _G.timerng:stats().sys.runs

    tracing.flush()

    -- wait for zero-delay timer
    helpers.wait_until(function ()
      local runs = _G.timerng:stats().sys.runs
      return runs_old < runs
    end)

    assert.stub(strategies.flushers.mock).was.called_with(
      ngx.ctx.kong_trace_traces,
      "mock_endpoint"
    )
  end)
end)
