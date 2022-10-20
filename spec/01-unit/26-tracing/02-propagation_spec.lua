local propagation = require "kong.tracing.propagation"

local to_hex = require "resty.string".to_hex

local table_merge = require "kong.tools.utils".table_merge

local fmt  = string.format

local function to_hex_ids(arr)
  return { arr[1],
           arr[2] and to_hex(arr[2]) or nil,
           arr[3] and to_hex(arr[3]) or nil,
           arr[4] and to_hex(arr[4]) or nil,
           arr[5] }
end

local function left_pad_zero(str, count)
  return ('0'):rep(count-#str) .. str
end

local parse = propagation.parse
local set = propagation.set
local from_hex = propagation.from_hex

local trace_id = "0000000000000001"
local big_trace_id = "fffffffffffffff1"
local trace_id_32 = "00000000000000000000000000000001"
local big_trace_id_32 = "fffffffffffffffffffffffffffffff1"
local parent_id = "0000000000000002"
local span_id = "0000000000000003"
local big_span_id = "fffffffffffffff3"
local non_hex_id = "vvvvvvvvvvvvvvvv"
local too_short_id = "123"
local too_long_id = "1234567890123456789012345678901234567890" -- 40 digits

describe("propagation.parse", function()

  _G.kong = {
    log = {},
  }

  describe("b3 single header parsing", function()
    local warn, debug
    setup(function()
      warn = spy.on(kong.log, "warn")
      debug = spy.on(kong.log, "debug")
    end)
    before_each(function()
      warn:clear()
      debug:clear()
    end)
    teardown(function()
      warn:revert()
      debug:clear()
    end)

    it("does not parse headers with ignore type", function()
      local b3 = fmt("%s-%s-%s-%s", trace_id, span_id, "1", parent_id)
      local t = { parse({ tracestate = "b3=" .. b3 }, "ignore") }
      assert.spy(warn).not_called()
      assert.same({}, t)
    end)

    it("1-char", function()
      local t  = { parse({ b3 = "1" }) }
      assert.same({ "b3-single", nil, nil, nil, true }, t)
      assert.spy(warn).not_called()

      t  = { parse({ b3 = "d" }) }
      assert.same({ "b3-single", nil, nil, nil, true }, t)
      assert.spy(warn).not_called()

      t  = { parse({ b3 = "0" }) }
      assert.same({ "b3-single", nil, nil, nil, false }, t)
      assert.spy(warn).not_called()
    end)

    it("4 fields", function()
      local b3 = fmt("%s-%s-%s-%s", trace_id, span_id, "1", parent_id)
      local t = { parse({ b3 = b3 }) }
      assert.same({ "b3-single", trace_id, span_id, parent_id, true }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("4 fields inside traceparent", function()
      local b3 = fmt("%s-%s-%s-%s", trace_id, span_id, "1", parent_id)
      local t = { parse({ tracestate = "b3=" .. b3 }) }
      assert.same({ "b3-single", trace_id, span_id, parent_id, true }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("32-digit trace_id", function()
      local b3 = fmt("%s-%s-%s-%s", trace_id_32, span_id, "1", parent_id)
      local t = { parse({ b3 = b3 }) }
      assert.same({ "b3-single", trace_id_32, span_id, parent_id, true }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("trace_id and span_id, no sample or parent_id", function()
      local b3 = fmt("%s-%s", trace_id, span_id)
      local t = { parse({ b3 = b3 }) }
      assert.same({ "b3-single", trace_id, span_id }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("32-digit trace_id and span_id, no sample or parent_id", function()
      local b3 = fmt("%s-%s", trace_id_32, span_id)
      local t = { parse({ b3 = b3 }) }
      assert.same({ "b3-single", trace_id_32, span_id }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("trace_id, span_id and sample, no parent_id", function()
      local b3 = fmt("%s-%s-%s", trace_id, span_id, "1")
      local t = { parse({ b3 = b3 }) }
      assert.same({ "b3-single", trace_id, span_id, nil, true }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("32-digit trace_id, span_id and sample, no parent_id", function()
      local b3 = fmt("%s-%s-%s", trace_id_32, span_id, "1")
      local t = { parse({ b3 = b3 }) }
      assert.same({ "b3-single", trace_id_32, span_id, nil, true }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("big 32-digit trace_id, span_id and sample, no parent_id", function()
      local b3 = fmt("%s-%s-%s", big_trace_id_32, span_id, "1")
      local t = { parse({ b3 = b3 }) }
      assert.same({ "b3-single", big_trace_id_32, span_id, nil, true }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("sample debug = always sample", function()
      local b3 = fmt("%s-%s-%s-%s", trace_id, span_id, "d", parent_id)
      local t  = { parse({ b3 = b3 }) }
      assert.same({ "b3-single", trace_id, span_id, parent_id, true }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("sample 0 = don't sample", function()
      local b3 = fmt("%s-%s-%s-%s", trace_id, span_id, "0", parent_id)
      local t  = { parse({ b3 = b3 }) }
      assert.same({ "b3-single", trace_id, span_id, parent_id, false }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("sample 0 overridden by x-b3-sampled", function()
      local b3 = fmt("%s-%s-%s-%s", trace_id, span_id, "0", parent_id)
      local t  = { parse({ b3 = b3, ["x-b3-sampled"] = "1" }) }
      assert.same({ "b3-single", trace_id, span_id, parent_id, true }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("multi value tracestate header", function()
      local tracestate_header = { "test", trace_id, span_id }
      local t = { parse({ tracestate =  tracestate_header }) }
      assert.same({ }, to_hex_ids(t))
      assert.spy(debug).called(1)
    end)

    describe("errors", function()
      it("requires trace id", function()
        local t = { parse({ b3 = "" }) }
        assert.same({"b3-single"}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")
      end)

      it("rejects existing but invalid trace_id", function()
        local t = { parse({ b3 = non_hex_id .. "-" .. span_id }) }
        assert.same({"b3-single"}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")

        t = { parse({ b3 = too_short_id .. "-" .. span_id }) }
        assert.same({"b3-single"}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")

        -- too long
        t = { parse({ b3 = too_long_id .. "-" .. span_id }) }
        assert.same({"b3-single"}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")
      end)

      it("requires span_id", function()
        local t = { parse({ b3 = trace_id .. "-" }) }
        assert.same({"b3-single"}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")
      end)

      it("rejects existing but invalid span_id", function()
        local t = { parse({ b3 = trace_id .. non_hex_id }) }
        assert.same({"b3-single"}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")

        t = { parse({ b3 = trace_id .. too_short_id }) }
        assert.same({"b3-single"}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")

        t = { parse({ b3 = trace_id .. too_long_id }) }
        assert.same({"b3-single"}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")
      end)

      it("rejects invalid sampled section", function()
        local b3 = fmt("%s-%s-%s-%s", trace_id, span_id, "x", parent_id)
        local t  = { parse({ b3 = b3 }) }
        assert.same({"b3-single"}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")
      end)

      it("rejects invalid parent_id section", function()
        local b3 = fmt("%s-%s-%s-%s", trace_id, span_id, "d", non_hex_id)
        local t  = { parse({ b3 = b3 }) }
        assert.same({"b3-single"}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")

        b3 = fmt("%s-%s-%s-%s", trace_id, span_id, "d", too_short_id)
        t  = { parse({ b3 = b3 }) }
        assert.same({"b3-single"}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")

        b3 = fmt("%s-%s-%s-%s", trace_id, span_id, "d", too_long_id)
        t  = { parse({ b3 = b3 }) }
        assert.same({"b3-single"}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")
      end)
    end)
  end)

  describe("W3C header parsing", function()
    local warn
    setup(function()
      warn = spy.on(kong.log, "warn")
    end)
    before_each(function()
      warn:clear()
    end)
    teardown(function()
      warn:revert()
    end)

    it("valid traceparent with sampling", function()
      local traceparent = fmt("00-%s-%s-01", trace_id_32, parent_id)
      local t = { parse({ traceparent = traceparent }) }
      assert.same({ "w3c", trace_id_32, nil, parent_id, true }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("valid traceparent without sampling", function()
      local traceparent = fmt("00-%s-%s-00", trace_id_32, parent_id)
      local t = { parse({ traceparent = traceparent }) }
      assert.same({ "w3c", trace_id_32, nil, parent_id, false }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("sampling with mask", function()
      local traceparent = fmt("00-%s-%s-09", trace_id_32, parent_id)
      local t = { parse({ traceparent = traceparent }) }
      assert.same({ "w3c", trace_id_32, nil, parent_id, true }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("no sampling with mask", function()
      local traceparent = fmt("00-%s-%s-08", trace_id_32, parent_id)
      local t = { parse({ traceparent = traceparent }) }
      assert.same({ "w3c", trace_id_32, nil, parent_id, false }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    describe("errors", function()
      it("rejects traceparent versions other than 00", function()
        local traceparent = fmt("01-%s-%s-00", trace_id_32, parent_id)
        local t = { parse({ traceparent = traceparent }) }
        assert.same({ "w3c" }, t)
        assert.spy(warn).was_called_with("invalid W3C Trace Context version; ignoring.")
      end)

      it("rejects invalid header", function()
        local traceparent = "vv-00000000000000000000000000000001-0000000000000001-00"
        local t = { parse({ traceparent = traceparent }) }
        assert.same({ "w3c" }, t)
        assert.spy(warn).was_called_with("invalid W3C traceparent header; ignoring.")

        traceparent = "00-vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv-0000000000000001-00"
        t = { parse({ traceparent = traceparent }) }
        assert.same({ "w3c" }, t)
        assert.spy(warn).was_called_with("invalid W3C traceparent header; ignoring.")

        traceparent = "00-00000000000000000000000000000001-vvvvvvvvvvvvvvvv-00"
        t = { parse({ traceparent = traceparent }) }
        assert.same({ "w3c" }, t)
        assert.spy(warn).was_called_with("invalid W3C traceparent header; ignoring.")

        traceparent = "00-00000000000000000000000000000001-0000000000000001-vv"
        t = { parse({ traceparent = traceparent }) }
        assert.same({ "w3c" }, t)
        assert.spy(warn).was_called_with("invalid W3C traceparent header; ignoring.")
      end)

      it("rejects invalid trace IDs", function()
        local traceparent = fmt("00-%s-%s-00", too_short_id, parent_id)
        local t = { parse({ traceparent = traceparent }) }
        assert.same({ "w3c" }, t)
        assert.spy(warn).was_called_with("invalid W3C trace context trace ID; ignoring.")

        traceparent = fmt("00-%s-%s-00", too_long_id, parent_id)
        t = { parse({ traceparent = traceparent }) }
        assert.same({ "w3c" }, t)
        assert.spy(warn).was_called_with("invalid W3C trace context trace ID; ignoring.")

        -- cannot be all zeros
        traceparent = fmt("00-00000000000000000000000000000000-%s-00", too_long_id, parent_id)
        t = { parse({ traceparent = traceparent }) }
        assert.same({ "w3c" }, t)
        assert.spy(warn).was_called_with("invalid W3C trace context trace ID; ignoring.")
      end)

      it("rejects invalid parent IDs", function()
        local traceparent = fmt("00-%s-%s-00", trace_id_32, too_short_id)
        local t = { parse({ traceparent = traceparent }) }
        assert.same({ "w3c" }, t)
        assert.spy(warn).was_called_with("invalid W3C trace context parent ID; ignoring.")

        traceparent = fmt("00-%s-%s-00", trace_id_32, too_long_id)
        t = { parse({ traceparent = traceparent }) }
        assert.same({ "w3c" }, t)
        assert.spy(warn).was_called_with("invalid W3C trace context parent ID; ignoring.")

        -- cannot be all zeros
        traceparent = fmt("00-%s-0000000000000000-01", trace_id_32)
        t = { parse({ traceparent = traceparent }) }
        assert.same({ "w3c" }, t)
        assert.spy(warn).was_called_with("invalid W3C trace context parent ID; ignoring.")
      end)

      it("rejects invalid trace flags", function()
        local traceparent = fmt("00-%s-%s-000", trace_id_32, parent_id)
        local t = { parse({ traceparent = traceparent }) }
        assert.same({ "w3c" }, t)
        assert.spy(warn).was_called_with("invalid W3C trace context flags; ignoring.")

        traceparent = fmt("00-%s-%s-0", trace_id_32, parent_id)
        t = { parse({ traceparent = traceparent }) }
        assert.same({ "w3c" }, t)
        assert.spy(warn).was_called_with("invalid W3C trace context flags; ignoring.")
      end)
    end)
  end)


  describe("Jaeger header parsing", function()
    local warn
    setup(function()
      warn = spy.on(kong.log, "warn")
    end)
    before_each(function()
      warn:clear()
    end)
    teardown(function()
      warn:revert()
    end)

    it("valid uber-trace-id with sampling", function()
      local ubertraceid = fmt("%s:%s:%s:%s", trace_id, span_id, parent_id, "1")
      local t = { parse({ ["uber-trace-id"] = ubertraceid }) }
      assert.same({ "jaeger", left_pad_zero(trace_id, 32), span_id, parent_id, true }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("valid uber-trace-id without sampling", function()
      local ubertraceid = fmt("%s:%s:%s:%s", trace_id, span_id, parent_id, "0")
      local t = { parse({ ["uber-trace-id"] = ubertraceid }) }
      assert.same({ "jaeger", left_pad_zero(trace_id, 32), span_id, parent_id, false }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("valid uber-trace-id 128bit with sampling", function()
      local ubertraceid = fmt("%s:%s:%s:%s", trace_id_32, span_id, parent_id, "1")
      local t = { parse({ ["uber-trace-id"] = ubertraceid }) }
      assert.same({ "jaeger", trace_id_32, span_id, parent_id, true }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("valid uber-trace-id 128bit without sampling", function()
      local ubertraceid = fmt("%s:%s:%s:%s", trace_id_32, span_id, parent_id, "0")
      local t = { parse({ ["uber-trace-id"] = ubertraceid }) }
      assert.same({ "jaeger", trace_id_32, span_id, parent_id, false }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("valid uber-trace-id with parent_id 0", function()
      local ubertraceid = fmt("%s:%s:%s:%s", trace_id, span_id, "0", "1")
      local t = { parse({ ["uber-trace-id"] = ubertraceid }) }
      assert.same({ "jaeger", left_pad_zero(trace_id, 32), span_id, to_hex("0"), true }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    describe("errors", function()
      it("rejects invalid header", function()
        local ubertraceid = fmt("vv:%s:%s:%s", span_id, parent_id, "0")
        local t = { parse({ ["uber-trace-id"] = ubertraceid }) }
        assert.same({ "jaeger" }, t)
        assert.spy(warn).was_called_with("invalid jaeger uber-trace-id header; ignoring.")

        ubertraceid = fmt("%s:vv:%s:%s", trace_id, parent_id, "0")
        t = { parse({ ["uber-trace-id"] = ubertraceid }) }
        assert.same({ "jaeger" }, t)
        assert.spy(warn).was_called_with("invalid jaeger uber-trace-id header; ignoring.")

        ubertraceid = fmt("%s:%s:vv:%s", trace_id, span_id,  "0")
        t = { parse({ ["uber-trace-id"] = ubertraceid }) }
        assert.same({ "jaeger" }, t)
        assert.spy(warn).was_called_with("invalid jaeger uber-trace-id header; ignoring.")

        ubertraceid = fmt("%s:%s:%s:vv", trace_id, span_id, parent_id)
        t = { parse({ ["uber-trace-id"] = ubertraceid }) }
        assert.same({ "jaeger" }, t)
        assert.spy(warn).was_called_with("invalid jaeger uber-trace-id header; ignoring.")
      end)

      it("rejects invalid trace IDs", function()
        local ubertraceid = fmt("%s:%s:%s:%s", too_long_id, span_id, parent_id, "1")
        local t = { parse({ ["uber-trace-id"] = ubertraceid }) }
        assert.same({ "jaeger" }, t)
        assert.spy(warn).was_called_with("invalid jaeger trace ID; ignoring.")

        -- cannot be all zeros
        ubertraceid = fmt("%s:%s:%s:%s", "00000000000000000000000000000000", span_id, parent_id, "1")
        t = { parse({ ["uber-trace-id"] = ubertraceid }) }
        assert.same({ "jaeger" }, t)
        assert.spy(warn).was_called_with("invalid jaeger trace ID; ignoring.")
      end)

      it("rejects invalid parent IDs", function()
        -- Ignores invalid parent id and logs
        local ubertraceid = fmt("%s:%s:%s:%s", trace_id, span_id, too_short_id, "1")
        local t = { parse({ ["uber-trace-id"] = ubertraceid }) }
        -- Note: to_hex(from_hex()) for too_short_id as the binary conversion from hex is resulting in a different number
        assert.same({ "jaeger", left_pad_zero(trace_id, 32), span_id, to_hex(from_hex(too_short_id)), true }, to_hex_ids(t))
        assert.spy(warn).was_called_with("invalid jaeger parent ID; ignoring.")

        -- Ignores invalid parent id and logs
        ubertraceid = fmt("%s:%s:%s:%s", trace_id, span_id, too_long_id, "1")
        t = { parse({ ["uber-trace-id"] = ubertraceid }) }
        assert.same({ "jaeger", left_pad_zero(trace_id, 32), span_id, too_long_id, true }, to_hex_ids(t))
        assert.spy(warn).was_called_with("invalid jaeger parent ID; ignoring.")
      end)

      it("rejects invalid span IDs", function()
        local ubertraceid = fmt("%s:%s:%s:%s", trace_id, too_long_id, parent_id, "1")
        local t = { parse({ ["uber-trace-id"] = ubertraceid }) }
        assert.same({ "jaeger" }, t)
        assert.spy(warn).was_called_with("invalid jaeger span ID; ignoring.")

        -- cannot be all zeros
        ubertraceid = fmt("%s:%s:%s:%s", trace_id, "00000000000000000000000000000000", parent_id, "1")
        t = { parse({ ["uber-trace-id"] = ubertraceid }) }
        assert.same({ "jaeger" }, t)
        assert.spy(warn).was_called_with("invalid jaeger span ID; ignoring.")
      end)

      it("rejects invalid trace flags", function()
        local ubertraceid = fmt("%s:%s:%s:%s", trace_id, span_id, parent_id, "123")
        local t = { parse({ ["uber-trace-id"] = ubertraceid }) }
        assert.same({ "jaeger" }, t)
        assert.spy(warn).was_called_with("invalid jaeger flags; ignoring.")
      end)

      it("0-pad shorter span IDs", function()
        local ubertraceid = fmt("%s:%s:%s:%s", trace_id, too_short_id, parent_id, "1")
        local t = { parse({ ["uber-trace-id"] = ubertraceid }) }
        assert.same({ "jaeger", left_pad_zero(trace_id, 32), left_pad_zero(too_short_id, 16), parent_id, true }, to_hex_ids(t))
      end)

      it("0-pad shorter trace IDs", function()
        local ubertraceid = fmt("%s:%s:%s:%s", too_short_id, span_id, parent_id, "1")
        local t = { parse({ ["uber-trace-id"] = ubertraceid }) }
        assert.same({ "jaeger", left_pad_zero(too_short_id, 32), span_id, parent_id, true }, to_hex_ids(t))
      end)
    end)
  end)


  describe("OT header parsing", function()
    local warn
    setup(function()
      warn = spy.on(kong.log, "warn")
    end)
    before_each(function()
      warn:clear()
    end)
    teardown(function()
      warn:revert()
    end)

    it("valid trace_id, valid span_id, sampled", function()
      local t = { parse({
        ["ot-tracer-traceid"] = trace_id,
        ["ot-tracer-spanid"] = span_id,
        ["ot-tracer-sampled"] = "1",
      })}
      assert.same({ "ot", trace_id, nil, span_id, true }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("valid big trace_id, valid big span_id, sampled", function()
      local t = { parse({
        ["ot-tracer-traceid"] = big_trace_id,
        ["ot-tracer-spanid"] = big_span_id,
        ["ot-tracer-sampled"] = "1",
      })}
      assert.same({ "ot", big_trace_id, nil, big_span_id, true }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("valid trace_id, valid span_id, not sampled", function()
      local t = { parse({
        ["ot-tracer-traceid"] = trace_id,
        ["ot-tracer-spanid"] = span_id,
        ["ot-tracer-sampled"] = "0",
      })}
      assert.same({ "ot", trace_id, nil, span_id, false }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("valid trace_id, valid span_id, sampled", function()
      local t = { parse({
        ["ot-tracer-traceid"] = trace_id,
        ["ot-tracer-spanid"] = span_id,
        ["ot-tracer-sampled"] = "1",
      })}
      assert.same({ "ot", trace_id, nil, span_id, true }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("valid trace_id, valid span_id, no sampled flag", function()
      local t = { parse({
        ["ot-tracer-traceid"] = trace_id,
        ["ot-tracer-spanid"] = span_id,
      })}
      assert.same({ "ot", trace_id, nil, span_id }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("32 trace_id, valid span_id, no sampled flag", function()
      local t = { parse({
        ["ot-tracer-traceid"] = trace_id_32,
        ["ot-tracer-spanid"] = span_id,
      })}
      assert.same({ "ot", trace_id_32, nil, span_id }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("big 32 trace_id, valid big_span_id, no sampled flag", function()
      local t = { parse({
        ["ot-tracer-traceid"] = big_trace_id_32,
        ["ot-tracer-spanid"] = big_span_id,
      })}
      assert.same({ "ot", big_trace_id_32, nil, big_span_id }, to_hex_ids(t))
      assert.spy(warn).not_called()
    end)

    it("valid trace_id, valid span_id, sampled, valid baggage added", function()
      local mock_key = "mock_key"
      local mock_value = "mock_value"
      local t = { parse({
        ["ot-tracer-traceid"] = trace_id,
        ["ot-tracer-spanid"] = span_id,
        ["ot-tracer-sampled"] = "1",
        ["ot-baggage-"..mock_key] = mock_value
      })}
      local mock_baggage_index = t[6]
      assert.same({ "ot", trace_id, nil, span_id, true }, to_hex_ids(t))
      assert.same(mock_baggage_index.mock_key, mock_value)
      assert.spy(warn).not_called()
    end)

    it("valid trace_id, valid span_id, sampled, invalid baggage added", function()
      local t = { parse({
        ["ot-tracer-traceid"] = trace_id,
        ["ot-tracer-spanid"] = span_id,
        ["ot-tracer-sampled"] = "1",
        ["ottttttttbaggage-foo"] = "invalid header"
      })}
      local mock_baggage_index = t[6]
      assert.same({ "ot", trace_id, nil, span_id, true }, to_hex_ids(t))
      assert.same(mock_baggage_index, nil)
      assert.spy(warn).not_called()
    end)
  end)
end)


describe("propagation.set", function()
  local nop = function() end

  local headers
  local warnings

  _G.kong = {
    service = {
      request = {
        set_header = function(name, value)
          headers[name] = value
        end,
      },
    },
    request = {
      get_header = nop,
    },
    log = {
      warn = function(msg)
        warnings[#warnings + 1] = msg
      end
    }
  }

  local proxy_span = {
    trace_id = from_hex(trace_id),
    span_id = from_hex(span_id),
    parent_id = from_hex(parent_id),
    should_sample = true,
    each_baggage_item = function() return nop end,
  }

  local b3_headers = {
    ["x-b3-traceid"] = trace_id,
    ["x-b3-spanid"] = span_id,
    ["x-b3-parentspanid"] = parent_id,
    ["x-b3-sampled"] = "1"
  }

  local b3_single_headers = {
    b3 = fmt("%s-%s-1-%s", trace_id, span_id, parent_id)
  }

  local w3c_headers = {
    traceparent = fmt("00-%s-%s-01", trace_id, span_id)
  }

  local jaeger_headers = {
    ["uber-trace-id"] = fmt("%s:%s:%s:%s", trace_id, span_id, parent_id, "01")
  }

  local ot_headers = {
    ["ot-tracer-traceid"] = trace_id,
    ["ot-tracer-spanid"] = span_id,
    ["ot-tracer-sampled"] = "1"
  }

  before_each(function()
    headers = {}
    warnings = {}
  end)

  describe("conf.header_type = 'preserve'", function()
    it("sets headers according to their found state when conf.header_type = preserve", function()
      set("preserve", "b3", proxy_span)
      assert.same(b3_headers, headers)

      headers = {}

      set("preserve", "b3-single", proxy_span)
      assert.same(b3_single_headers, headers)

      headers = {}

      set("preserve", "w3c", proxy_span)
      assert.same(w3c_headers, headers)

      headers = {}

      set("preserve", "jaeger", proxy_span)
      assert.same(jaeger_headers, headers)

      assert.same({}, warnings)
    end)

    it("sets headers according to default_header_type when no headers are provided", function()
      set("preserve", nil, proxy_span)
      assert.same(b3_headers, headers)

      headers = {}

      set("preserve", nil, proxy_span, "b3")
      assert.same(b3_headers, headers)

      headers = {}

      set("preserve", nil, proxy_span, "b3-single")
      assert.same(b3_single_headers, headers)

      headers = {}

      set("preserve", "w3c", proxy_span, "w3c")
      assert.same(w3c_headers, headers)

      headers = {}

      set("preserve", nil, proxy_span, "jaeger")
      assert.same(jaeger_headers, headers)

      headers = {}

      set("preserve", "ot", proxy_span, "ot")
      assert.same(ot_headers, headers)
    end)
  end)

  describe("conf.header_type = 'b3'", function()
    it("sets headers to b3 when conf.header_type = b3", function()
      set("b3", "b3", proxy_span)
      assert.same(b3_headers, headers)

      headers = {}

      set("b3", nil, proxy_span)
      assert.same(b3_headers, headers)

      assert.same({}, warnings)
    end)

    it("sets both the b3 and b3-single headers when a b3-single header is encountered.", function()
      set("b3", "b3-single", proxy_span)
      assert.same(table_merge(b3_headers, b3_single_headers), headers)

      -- but it generates a warning
      assert.equals(1, #warnings)
      assert.matches("Mismatched header types", warnings[1])
    end)

    it("sets both the b3 and w3c headers when a w3c header is encountered.", function()
      set("b3", "w3c", proxy_span)
      assert.same(table_merge(b3_headers, w3c_headers), headers)

      -- but it generates a warning
      assert.equals(1, #warnings)
      assert.matches("Mismatched header types", warnings[1])
    end)

    it("sets both the b3 and w3c headers when a jaeger header is encountered.", function()
      set("b3", "jaeger", proxy_span)
      assert.same(table_merge(b3_headers, jaeger_headers), headers)

      -- but it generates a warning
      assert.equals(1, #warnings)
      assert.matches("Mismatched header types", warnings[1])
    end)
  end)

  describe("conf.header_type = 'b3-single'", function()
    it("sets headers to b3-single when conf.header_type = b3-single", function()
      set("b3-single", "b3-single", proxy_span)
      assert.same(b3_single_headers, headers)
      assert.same({}, warnings)
    end)

    it("sets both the b3 and b3-single headers when a b3 header is encountered.", function()
      set("b3-single", "b3", proxy_span)
      assert.same(table_merge(b3_headers, b3_single_headers), headers)

      -- but it generates a warning
      assert.equals(1, #warnings)
      assert.matches("Mismatched header types", warnings[1])
    end)

    it("sets both the b3 and w3c headers when a w3c header is encountered.", function()
      set("b3-single", "w3c", proxy_span)
      assert.same(table_merge(b3_single_headers, w3c_headers), headers)

      -- but it generates a warning
      assert.equals(1, #warnings)
      assert.matches("Mismatched header types", warnings[1])
    end)

    it("sets both the b3 and w3c headers when a w3c header is encountered.", function()
      set("b3-single", "jaeger", proxy_span)
      assert.same(table_merge(b3_single_headers, jaeger_headers), headers)

      -- but it generates a warning
      assert.equals(1, #warnings)
      assert.matches("Mismatched header types", warnings[1])
    end)
  end)

  describe("conf.header_type = 'w3c'", function()
    it("sets headers to w3c when conf.header_type = w3c", function()
      set("w3c", "w3c", proxy_span)
      assert.same(w3c_headers, headers)
      assert.same({}, warnings)
    end)

    it("sets both the b3 and w3c headers when a w3c header is encountered.", function()
      set("w3c", "b3", proxy_span)
      assert.same(table_merge(b3_headers, w3c_headers), headers)

      -- but it generates a warning
      assert.equals(1, #warnings)
      assert.matches("Mismatched header types", warnings[1])
    end)

    it("sets both the b3-single and w3c headers when a b3-single header is encountered.", function()
      set("w3c", "b3-single", proxy_span)
      assert.same(table_merge(b3_single_headers, w3c_headers), headers)

      -- but it generates a warning
      assert.equals(1, #warnings)
      assert.matches("Mismatched header types", warnings[1])
    end)

    it("sets both the jaeger and w3c headers when a b3-single header is encountered.", function()
      set("w3c", "jaeger", proxy_span)
      assert.same(table_merge(jaeger_headers, w3c_headers), headers)

      -- but it generates a warning
      assert.equals(1, #warnings)
      assert.matches("Mismatched header types", warnings[1])
    end)
  end)

  describe("conf.header_type = 'jaeger'", function()
    it("sets headers to jaeger when conf.header_type = jaeger", function()
      set("jaeger", "jaeger", proxy_span)
      assert.same(jaeger_headers, headers)
      assert.same({}, warnings)
    end)

    it("sets both the b3 and jaeger headers when a jaeger header is encountered.", function()
      set("jaeger", "b3", proxy_span)
      assert.same(table_merge(b3_headers, jaeger_headers), headers)

      -- but it generates a warning
      assert.equals(1, #warnings)
      assert.matches("Mismatched header types", warnings[1])
    end)

    it("sets both the b3-single and jaeger headers when a b3-single header is encountered.", function()
      set("jaeger", "b3-single", proxy_span)
      assert.same(table_merge(b3_single_headers, jaeger_headers), headers)

      -- but it generates a warning
      assert.equals(1, #warnings)
      assert.matches("Mismatched header types", warnings[1])
    end)

    it("sets both the jaeger and w3c headers when a w3c header is encountered.", function()
      set("jaeger", "w3c", proxy_span)
      assert.same(table_merge(jaeger_headers, w3c_headers), headers)

      -- but it generates a warning
      assert.equals(1, #warnings)
      assert.matches("Mismatched header types", warnings[1])
    end)

    it("sets both the jaeger and ot headers when a ot header is encountered.", function()
      set("jaeger", "ot", proxy_span)
      assert.same(table_merge(jaeger_headers, ot_headers), headers)

      -- but it generates a warning
      assert.equals(1, #warnings)
      assert.matches("Mismatched header types", warnings[1])
    end)
  end)

  describe("conf.header_type = 'ot'", function()
    it("sets headers to ot when conf.header_type = ot", function()
      set("ot", "ot", proxy_span)
      assert.same(ot_headers, headers)
      assert.same({}, warnings)
    end)

    it("sets both the b3 and ot headers when a ot header is encountered.", function()
      set("ot", "b3", proxy_span)
      assert.same(table_merge(b3_headers, ot_headers), headers)

      -- but it generates a warning
      assert.equals(1, #warnings)
      assert.matches("Mismatched header types", warnings[1])
    end)

    it("sets both the b3-single and ot headers when a ot header is encountered.", function()
      set("ot", "b3-single", proxy_span)
      assert.same(table_merge(b3_single_headers, ot_headers), headers)

      -- but it generates a warning
      assert.equals(1, #warnings)
      assert.matches("Mismatched header types", warnings[1])
    end)

    it("sets both the w3c and ot headers when a ot header is encountered.", function()
      set("ot", "w3c", proxy_span)
      assert.same(table_merge(w3c_headers, ot_headers), headers)

      -- but it generates a warning
      assert.equals(1, #warnings)
      assert.matches("Mismatched header types", warnings[1])
    end)

    it("sets both the ot and jaeger headers when a jaeger header is encountered.", function()
      set("ot", "jaeger", proxy_span)
      assert.same(table_merge(ot_headers, jaeger_headers), headers)

      -- but it generates a warning
      assert.equals(1, #warnings)
      assert.matches("Mismatched header types", warnings[1])
    end)
  end)

end)
