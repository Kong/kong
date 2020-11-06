-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local strategies = require "kong.tracing.strategies"

describe(".flush", function()
  local tracing = require "kong.tracing"

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

  it("flushes traces via configured write strategy/endpoint", function()
    strategies.flushers = {
      mock = function(traces, endpoint) end
    }

    mock(strategies.flushers)

    local trace = tracing.trace("foo")
    assert.same("foo", trace.name)
    trace:finish()

    tracing.flush()

    ngx.sleep(0.1)

    assert.stub(strategies.flushers.mock).was.called_with(
      ngx.ctx.kong_trace_traces,
      "mock_endpoint"
    )
  end)
end)
