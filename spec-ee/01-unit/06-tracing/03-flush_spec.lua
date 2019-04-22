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

    ngx.get_phase = function() return "foo" end
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
