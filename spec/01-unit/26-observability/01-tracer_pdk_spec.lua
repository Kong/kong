require "spec.helpers" -- initializes 'kong' global for tracer
local match = require("luassert.match")

local SAMPLING_BYTE = 8
local rand_bytes = require("kong.tools.rand").get_rand_bytes
local TEST_COUNT = 10000
-- we can only ensure a sampling precision of 0.02
local SAMPLING_PRECISION = 0.02

local function assert_sample_rate(actual, expected)
  local diff = math.abs(actual - expected)
  assert(diff < SAMPLING_PRECISION, "sampling rate is not correct: " .. actual .. " expected: " .. expected)
end

describe("Tracer PDK", function()
  local ok, err, old_ngx_get_phase, _
  local log_spy

  lazy_setup(function()
    local kong_global = require "kong.global"
    _G.kong = kong_global.new()
    kong_global.init_pdk(kong)
    log_spy = spy.on(ngx, "log")
    old_ngx_get_phase = ngx.get_phase
    -- trick the pdk into thinking we are not in the timer context
    _G.ngx.get_phase = function() return "access" end  -- luacheck: ignore
  end)

  lazy_teardown(function()
    _G.ngx.get_phase = old_ngx_get_phase  -- luacheck: ignore
  end)

  describe("initialize tracer", function()

    it("tracer instance created", function ()
      ok, err = pcall(require "kong.pdk.tracing".new)
      assert.is_true(ok, err)

      ok, err = pcall(kong.tracing.new, "tracer")
      assert.is_true(ok, err)
    end)

    it("default tracer instance", function ()
      local tracer
      tracer = require "kong.pdk.tracing".new()
      assert.same("noop", tracer.name)
    end)

    it("noop tracer has same functions and config as normal tracer", function ()
      local tracer = require "kong.pdk.tracing".new().new("real")
      local noop_tracer = require "kong.pdk.tracing".new()
      local ignore_list = {
        sampler = 1,
        active_span_key = 1,
      }
      for k, _ in pairs(tracer) do
        if ignore_list[k] ~= 1 then
          assert.not_nil(noop_tracer[k], k)
        end
      end
    end)

    it("global tracer", function ()
      -- Noop tracer
      assert.same(kong.tracing, require "kong.pdk.tracing".new())
      assert.same(kong.tracing, kong.tracing.new("noop", { noop = true }))
    end)

    it("replace global tracer", function ()
      local new_tracer = kong.tracing.new()
      kong.tracing.set_global_tracer(new_tracer)

      assert.same(new_tracer, kong.tracing)
      assert.same(new_tracer, require "kong.pdk.tracing".new())

      package.loaded["kong.pdk.tracing"] = nil
      local kong_global = require "kong.global"
      _G.kong = kong_global.new()
      kong_global.init_pdk(kong)
    end)

  end)

  describe("span spec", function ()
    -- common tracer
    local c_tracer = kong.tracing.new("normal")
    -- noop tracer
    local n_tracer = require "kong.pdk.tracing".new()

    before_each(function()
      ngx.ctx.KONG_SPANS = nil
      c_tracer.set_active_span(nil)
      n_tracer.set_active_span(nil)
    end)

    it("fails when span name is empty", function ()
      -- create
      ok, _ = pcall(c_tracer.start_span)
      assert.is_false(ok)

      -- 0-length name
      ok, _ = pcall(c_tracer.start_span, "")
      assert.is_false(ok)
    end)

    it("create noop span with noop tracer", function ()
      local span = n_tracer.start_span("meow")
      assert.is_nil(span.span_id)
      assert.is_nil(span.tracer)
    end)

    it("noop span operations", function ()
      local span = n_tracer.start_span("meow")
      assert(pcall(span.set_attribute, span, "foo", "bar"))
      assert(pcall(span.add_event, span, "foo", "bar"))
      assert(pcall(span.finish, span))
    end)

    it("fails create span with options", function ()
      assert.error(function () c_tracer.start_span("") end)
      assert.error(function () c_tracer.start_span("meow", { start_time_ns = "" }) end)
      assert.error(function () c_tracer.start_span("meow", { span_kind = "" }) end)
      assert.error(function () c_tracer.start_span("meow", { should_sample = "" }) end)
      assert.error(function () c_tracer.start_span("meow", { attributes = "" }) end)
    end)

    it("default span value length", function ()
      local span
      span = c_tracer.start_span("meow")
      assert.same(16, #span.trace_id)
      assert.same(8, #span.span_id)
      assert.is_true(span.start_time_ns > 0)
    end)

    it("create span with options", function ()
      local span

      local tpl = {
        name = "meow",
        trace_id = "000000000000",
        start_time_ns = ngx.now() * 100000000,
        parent_id = "",
        should_sample = true,
        kind = 1,
        attributes = {
          "key1", "value1"
        },
        linked = true,
      }

      span = c_tracer.start_span("meow", tpl)
      local c_span = table.clone(span)
      c_span.tracer = nil
      c_span.span_id = nil
      c_span.parent = nil
      assert.same(tpl, c_span)

      assert.has_no.error(function () span:finish() end)
    end)

    it("set_attribute validation", function ()
      local span = c_tracer.start_span("meow")

      -- nil value is allowed as a noop
      span:set_attribute("key1")
      assert.spy(log_spy).was_not_called_with(ngx.ERR, match.is_string())
      assert.is_nil(span.attributes["key1"])

      span:set_attribute("key1", "value1")
      assert.equal("value1", span.attributes["key1"])

      -- nil value unsets the attribute
      span:set_attribute("key1")
      assert.is_nil(span.attributes["key1"])

      span:set_attribute("key1", function() end)
      assert.spy(log_spy).was_called_with(ngx.ERR, match.is_string())

      assert.error(function() span:set_attribute(123, 123) end)
    end)

    it("fails add_event", function ()
      local span = c_tracer.start_span("meow")
      assert.error(function() span:add_event("key1", 123) end)
      assert.error(function() span:add_event("key1", function() end) end)
      assert.error(function() span:add_event(123, {}) end)
    end)

    it("child spans", function ()
      local root_span = c_tracer.start_span("parent")
      c_tracer.set_active_span(root_span)
      local child_span = c_tracer.start_span("child")

      assert.same(root_span.span_id, child_span.parent_id)

      local second_child_span = c_tracer.start_span("child2")
      assert.same(root_span.span_id, second_child_span.parent_id)
      assert.are_not.same(child_span.span_id, second_child_span.parent_id)

      c_tracer.set_active_span(child_span)
      local third_child_span = c_tracer.start_span("child2")
      assert.same(child_span.span_id, third_child_span.parent_id)
    end)

    it("cascade spans", function ()
      local root_span = c_tracer.start_span("root")
      c_tracer.set_active_span(root_span)

      assert.same(root_span, c_tracer.active_span())

      local level1_span = c_tracer.start_span("level1")
      assert.same(root_span, level1_span.parent)

      c_tracer.set_active_span(level1_span)
      assert.same(level1_span, c_tracer.active_span())

      local level2_span = c_tracer.start_span("level2")
      assert.same(level1_span, level2_span.parent)

      local level21_span = c_tracer.start_span("level2.1")
      assert.same(level1_span, level21_span.parent)
      level21_span:finish()

      c_tracer.set_active_span(level2_span)
      assert.same(level2_span, c_tracer.active_span())

      local level3_span = c_tracer.start_span("level3")
      assert.same(level2_span, level3_span.parent)
      level3_span:finish()

      level2_span:finish()
      assert.same(level1_span, c_tracer.active_span())

      level1_span:finish()
      assert.same(root_span, c_tracer.active_span())
    end)

    it("access span table after finished", function ()
      local span = c_tracer.start_span("meow")
      span:finish()
      assert.has_no.error(function () span:finish() end)
    end)

    it("ends span", function ()
      local span = c_tracer.start_span("meow")
      c_tracer.set_active_span(span)

      -- create sub spans
      local sub = c_tracer.start_span("sub")
      sub:finish()
      sub = c_tracer.start_span("sub")
      sub:finish()

      local active_span = c_tracer.active_span()
      assert.same(span, active_span)
      assert.has_no.error(function () active_span:finish() end)

      -- span's property is still accessible
      assert.same("meow", active_span.name)
    end)

    it("release span", function ()
      local span = c_tracer.start_span("foo")
      -- clear span table
      span:release()
      assert.same({}, span)
    end)

    for _, len in ipairs{8, 16, 9, 32, 5} do
      it("#10402 sample rate works for traceID of length " .. len, function ()
        -- a random sample rate
        local rand_offset = math.random(-10000, 10000) * 0.0000001
        local sampling_rate = 0.5 + rand_offset
        local tracer = c_tracer.new("test",{
          sampling_rate = sampling_rate,
        })
  
        -- we need to confirm the desired sampling rate is achieved
        local sample_count = 0

        -- we also need to confirm the sampler have the same output for the same input
        local result = {}

        local function gen_id()
          return rand_bytes(len)
        end

        -- for cases where the traceID is too short
        if len < SAMPLING_BYTE then
          local sampled, err = tracer.sampler(gen_id())
          assert.is_nil(sampled)
          assert.matches("sampling needs trace ID to be longer than", err)
          return
        end
  
        for i = 1, TEST_COUNT do
          local trace_id = gen_id()
          local sampled = tracer.sampler(trace_id)
          if sampled then
            sample_count = sample_count + 1
          end
          result[trace_id] = sampled
        end
        
        -- confirm the sampling rate
        local actual_rate = sample_count / TEST_COUNT
        assert_sample_rate(actual_rate, sampling_rate)

        -- only verify 100 times so the test won't take too long
        local verified_count = 0
        -- confirm the sampler is deterministic
        for k, v in pairs(result) do
          assert.same(v, tracer.sampler(k))
          verified_count = verified_count + 1
          if verified_count > 100 then
            break
          end
        end
      end)
    end
  end)

end)
