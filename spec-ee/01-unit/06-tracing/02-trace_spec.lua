local uuid = require("kong.tools.utils").uuid

describe(".trace", function()
  local tracing = require "kong.tracing"

  describe("enabled", function()
    setup(function()
      tracing.init({
        tracing = true,
        tracing_types = { "all" },
        tracing_time_threshold = 0,
        generate_trace_details = true,
      })

      ngx.get_phase = function() return "foo" end
    end)

    it("creates a trace object", function()
      local trace = tracing.trace("foo")

      assert.equals("foo", trace.name)
      assert.same({}, trace.data)
      assert.is_nil(trace.parent)
      assert.same({ trace.id }, ngx.ctx.kong_trace_parent)
    end)

    it("creates a trace object with ctx data", function()
      local trace = tracing.trace("foo", {
        yo = "mama",
      })

      assert.equals("foo", trace.name)
      assert.same({ yo = "mama" }, trace.data)
    end)

    it("creates a trace object without a catchall function handler", function()
      local trace = tracing.trace("foo")

      assert.has_errors(function() trace:dne() end)
    end)

    describe("with a parent trace", function()
      local parent_id = uuid()

      setup(function()
        ngx.ctx.kong_trace_parent = { parent_id }
      end)

      it("creates a trace object", function()
        local trace = tracing.trace("foo")

        assert.same(parent_id, trace.parent)
        assert.same(2, #ngx.ctx.kong_trace_parent)
        assert.same({ parent_id, trace.id }, ngx.ctx.kong_trace_parent)
      end)
    end)

    describe(":finish()", function()
      local trace1, trace2

      setup(function()
        ngx.ctx.kong_trace_parent = nil
        ngx.ctx.kong_trace_traces = nil
      end)

      it("buffers a trace object", function()
        trace1 = tracing.trace("foo")

        -- :finish has no return
        assert.has_no.errors(function() trace1:finish() end)

        assert.is_number(trace1.done)
        assert.is_number(trace1.duration)

        assert.same({}, ngx.ctx.kong_trace_parent)
        assert.same({ trace1 }, ngx.ctx.kong_trace_traces)
      end)

      it("buffers a second trace object", function()
        trace2 = tracing.trace("bar")

        assert.has_no.errors(function() trace2:finish() end)

        assert.same({}, ngx.ctx.kong_trace_parent)
        assert.same({ trace1, trace2 }, ngx.ctx.kong_trace_traces)
      end)

      it("does not buffer an object with an out-of-range threshold", function()
        local trace = tracing.trace("baz")

        trace.start = trace.start + 1e5

        assert.has_no.errors(function() trace:finish() end)

        assert.same({}, ngx.ctx.kong_trace_parent)
        assert.same({ trace1, trace2 }, ngx.ctx.kong_trace_traces)
      end)

      it("errors when called multiple times", function()
        local trace = tracing.trace("bat")

        assert.has_no.errors(function() trace:finish() end)
        assert.has.errors(function() trace:finish() end)
      end)
    end)

    describe(":add_data()", function()
      setup(function()
        ngx.ctx.kong_trace_parent = nil
        ngx.ctx.kong_trace_traces = nil
      end)

      describe("adds additional data to the trace object", function()
        it("with an empty initialized ctx", function()
          local trace = tracing.trace("foo")

          assert(trace:add_data("foo", "bar"))

          assert.equals(trace.data.foo, "bar")
        end)

        it("with an existing initialized ctx", function()
          local trace = tracing.trace("foo", {
            baz = "bat"
          })

          assert(trace:add_data("foo", "bar"))

          assert.equals(trace.data.foo, "bar")
          assert.equals(trace.data.baz, "bat")
        end)
      end)

      describe("overwrites existing ctx data", function()
        it("from an initialized ctx", function()
          local trace = tracing.trace("foo", {
            baz = "bat"
          })

          assert(trace:add_data("baz", "batty"))

          assert.equals(trace.data.baz, "batty")
        end)

        it("from a previous add_data call", function()
          local trace = tracing.trace("foo")

          assert(trace:add_data("foo", "bar"))
          assert.equals(trace.data.foo, "bar")

          assert(trace:add_data("foo", "baz"))
          assert.equals(trace.data.foo, "baz")
        end)
      end)
    end)

    describe("in an invalid phase", function()
      setup(function()
        ngx.get_phase = function() return "timer" end
      end)

      it("creates an empty object", function()
        local trace = tracing.trace("foo")

        assert.same({}, trace)
      end)
    end)
  end)

  describe("enabled with specific types", function()
    setup(function()
      tracing.init({
        tracing = true,
        tracing_types = { "foo", "bar" },
        tracing_time_threshold = 0,
      })

      ngx.get_phase = function() return "foo" end
    end)

    it("creates a trace object with a configured type", function()
      local trace = tracing.trace("foo")

      assert.same(trace.name, "foo")
    end)

    it("does not create a trace with an unconfigured type", function()
      local trace = tracing.trace("baz")

      assert.same({}, trace)
    end)
  end)

  describe("enabled without generate_trace_details", function()
    setup(function()
      tracing.init({
        tracing = true,
        tracing_types = { "foo", "bar" },
        tracing_time_threshold = 0,
        generate_trace_data = false
      })

      ngx.get_phase = function() return "foo" end
    end)

    it("creates a trace object without any initialized data", function()
      local trace = tracing.trace("foo")

      trace:finish()

      assert.is_nil(trace.data)
    end)

    it("creates a trace object without any data", function()
      local trace = tracing.trace("foo", { bar = true })

      trace:finish()

      assert.is_nil(trace.data)
    end)

    it("creates a trace object without any added data", function()
      local trace = tracing.trace("foo")

      trace:add_data("bar", true)

      trace:finish()

      assert.is_nil(trace.data)
    end)
  end)

  describe("disabled", function()
    setup(function()
      tracing.init({
        tracing = false,
        tracing_types = { "all" },
      })
    end)

    it("creates an empty object", function()
      local trace = tracing.trace("foo")

      assert.same({}, trace)
    end)
  end)
end)
