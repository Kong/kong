require "spec.helpers"
require "kong.plugins.opentelemetry.proto"
local otlp = require "kong.plugins.opentelemetry.otlp"
local pb = require "pb"

local fmt = string.format
local rand_bytes = require("kong.tools.rand").get_rand_bytes
local time_ns = require("kong.tools.time").time_ns
local deep_copy = require("kong.tools.table").deep_copy
local insert = table.insert
local tracer = kong.tracing.new("test")

local function table_compare(expected, passed)
  if type(expected) ~= type(passed) then
    return false, fmt("expected: %s, got: %s", type(expected), type(passed))
  end

  for k, v in pairs(expected) do
    local v_typ = type(v)
    if v_typ == "nil"
      or v_typ == "number"
      or v_typ == "string"
      or v_typ == "boolean"
    then
      if v ~= passed[k] then
        return false, fmt("%s field, expected: %s, got: %s", k, v, passed[k])
      end

    elseif v_typ == "table" and #v > 0 then
      local ok, err = table_compare(v, passed[k])
      return ok, fmt("%s field, %s", k, err)
    end
  end

  return true
end

local pb_encode_span = function(data)
  return pb.encode("opentelemetry.proto.trace.v1.Span", data)
end

local pb_decode_span = function(data)
  return pb.decode("opentelemetry.proto.trace.v1.Span", data)
end

local pb_encode_log = function(data)
  return pb.encode("opentelemetry.proto.logs.v1.LogRecord", data)
end

local pb_decode_log = function(data)
  return pb.decode("opentelemetry.proto.logs.v1.LogRecord", data)
end

describe("Plugin: opentelemetry (otlp)", function()
  local old_ngx_get_phase

  lazy_setup(function ()
    -- overwrite for testing
    pb.option("enum_as_value")
    pb.option("auto_default_values")
    old_ngx_get_phase = ngx.get_phase
    -- trick the pdk into thinking we are not in the timer context
    _G.ngx.get_phase = function() return "access" end  -- luacheck: ignore
  end)

  lazy_teardown(function()
    -- revert it back
    pb.option("enum_as_name")
    pb.option("no_default_values")
    _G.ngx.get_phase = old_ngx_get_phase  -- luacheck: ignore
  end)

  after_each(function ()
    ngx.ctx.KONG_SPANS = nil
  end)

  it("encode/decode pb (traces)", function ()
    local N = 10000

    local test_spans = {
      -- default one
      {
        name = "full-span",
        trace_id = rand_bytes(16),
        span_id = rand_bytes(8),
        parent_id = rand_bytes(8),
        start_time_ns = time_ns(),
        end_time_ns = time_ns() + 1000,
        should_sample = true,
        attributes = {
          foo = "bar",
          test = true,
          version = 0.1,
        },
        events = {
          {
            name = "evt1",
            time_ns = time_ns(),
            attributes = {
              debug = true,
            }
          }
        },
      },
    }

    for i = 1, N do
      local span = tracer.start_span(tostring(i), {
        span_kind = i % 6,
        attributes = {
          str = fmt("tag-%s", i),
          int = i,
          bool = (i % 2 == 0 and true) or false,
          double = i / (N * 1000),
        },
      })

      span:set_status(i % 3)
      span:add_event(tostring(i), span.attributes)
      span:finish()

      insert(test_spans, table.clone(span))
      span:release()
    end

    for _, test_span in ipairs(test_spans) do
      local pb_span = otlp.transform_span(test_span)
      local pb_data = pb_encode_span(pb_span)
      local decoded_span = pb_decode_span(pb_data)

      local ok, err = table_compare(pb_span, decoded_span)
      assert.is_true(ok, err)
    end
  end)

  it("encode/decode pb (logs)", function ()
    local N = 10000

    local test_logs = {}

    for _ = 1, N do
      local now_ns = time_ns()

      local log = {
        time_unix_nano = now_ns,
        observed_time_unix_nano = now_ns,
        log_level = ngx.INFO,
        span_id = rand_bytes(8),
        body = "log line",
        attributes = {
          foo = "bar",
          test = true,
          version = 0.1,
        },
      }
      insert(test_logs, log)
    end

    local trace_id = rand_bytes(16)
    local flags = tonumber(rand_bytes(1))
    local prepared_logs = otlp.prepare_logs(test_logs, trace_id, flags)

    for _, prepared_log in ipairs(prepared_logs) do
      local decoded_log = pb_decode_log(pb_encode_log(prepared_log))

      local ok, err = table_compare(prepared_log, decoded_log)
      assert.is_true(ok, err)
    end
  end)

  it("check lengths of trace_id and span_id ", function ()
    local TRACE_ID_LEN, PARENT_SPAN_ID_LEN = 16, 8
    local default_span = {
      name = "full-span",
      trace_id = rand_bytes(16),
      span_id = rand_bytes(8),
      parent_id = rand_bytes(8),
      start_time_ns = time_ns(),
      end_time_ns = time_ns() + 1000,
      should_sample = true,
      attributes = {
        foo = "bar",
        test = true,
        version = 0.1,
      },
      events = {
        {
          name = "evt1",
          time_ns = time_ns(),
          attributes = {
            debug = true,
          }
        }
      },
    }

    local test_spans = {}
    local span1 = deep_copy(default_span)
    local span2 = deep_copy(default_span)
    span1.trace_id = rand_bytes(17)
    span1.expected_tid = span1.trace_id:sub(-TRACE_ID_LEN)
    span1.parent_id = rand_bytes(9)
    span1.expected_pid = span1.parent_id:sub(-PARENT_SPAN_ID_LEN)
    span2.trace_id = rand_bytes(15)
    span2.expected_tid = '\0' .. span2.trace_id
    span2.parent_id = rand_bytes(7)
    span2.expected_pid = '\0' .. span2.parent_id
    insert(test_spans, span1)
    insert(test_spans, span2)

    for _, span in ipairs(test_spans) do
      local pb_span = otlp.transform_span(span)
      assert(pb_span.parent_span_id == span.expected_pid)
      assert(pb_span.trace_id == span.expected_tid)
    end
  end)

end)
