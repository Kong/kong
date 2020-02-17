local parse_http_req_headers = require "kong.plugins.zipkin.parse_http_req_headers"

local to_hex = require "resty.string".to_hex

local fmt  = string.format

local function to_hex_first_3(arr)
  return { arr[1] and to_hex(arr[1]) or nil,
           arr[2] and to_hex(arr[2]) or nil,
           arr[3] and to_hex(arr[3]) or nil,
           arr[4] }
end


local trace_id = "0000000000000001"
local trace_id_32 = "00000000000000000000000000000001"
local parent_id = "0000000000000002"
local span_id = "0000000000000003"
local non_hex_id = "vvvvvvvvvvvvvvvv"
local too_short_id = "123"
local too_long_id = "1234567890123456789012345678901234567890" -- 40 digits


describe("zipkin header parsing", function()

  _G.kong = {
    log = {},
  }

  describe("b3 single header parsing", function()
    local warn
    before_each(function()
      warn = spy.on(kong.log, "warn")
    end)

    it("1-char", function()
      local t  = { parse_http_req_headers({ b3 = "1" }) }
      assert.same({ nil, nil, nil, true }, t)
      assert.spy(warn).not_called()

      t  = { parse_http_req_headers({ b3 = "d" }) }
      assert.same({ nil, nil, nil, true }, t)
      assert.spy(warn).not_called()

      t  = { parse_http_req_headers({ b3 = "0" }) }
      assert.same({ nil, nil, nil, false }, t)
      assert.spy(warn).not_called()
    end)

    it("4 fields", function()
      local b3 = fmt("%s-%s-%s-%s", trace_id, span_id, "1", parent_id)
      local t = { parse_http_req_headers({ b3 = b3 }) }
      assert.same({ trace_id, span_id, parent_id, true }, to_hex_first_3(t))
      assert.spy(warn).not_called()
    end)

    it("4 fields inside tracestate", function()
      local b3 = fmt("%s-%s-%s-%s", trace_id, span_id, "1", parent_id)
      local t = { parse_http_req_headers({ tracestate = "b3=" .. b3 }) }
      assert.same({ trace_id, span_id, parent_id, true }, to_hex_first_3(t))
      assert.spy(warn).not_called()
    end)

    it("32-digit trace_id", function()
      local b3 = fmt("%s-%s-%s-%s", trace_id_32, span_id, "1", parent_id)
      local t = { parse_http_req_headers({ b3 = b3 }) }
      assert.same({ trace_id_32, span_id, parent_id, true }, to_hex_first_3(t))
      assert.spy(warn).not_called()
    end)

    it("trace_id and span_id, no sample or parent_id", function()
      local b3 = fmt("%s-%s", trace_id, span_id)
      local t = { parse_http_req_headers({ b3 = b3 }) }
      assert.same({ trace_id, span_id }, to_hex_first_3(t))
      assert.spy(warn).not_called()
    end)

    it("32-digit trace_id and span_id, no sample or parent_id", function()
      local b3 = fmt("%s-%s", trace_id_32, span_id)
      local t = { parse_http_req_headers({ b3 = b3 }) }
      assert.same({ trace_id_32, span_id }, to_hex_first_3(t))
      assert.spy(warn).not_called()
    end)

    it("trace_id, span_id and sample, no parent_id", function()
      local b3 = fmt("%s-%s-%s", trace_id, span_id, "1")
      local t = { parse_http_req_headers({ b3 = b3 }) }
      assert.same({ trace_id, span_id, nil, true }, to_hex_first_3(t))
      assert.spy(warn).not_called()
    end)

    it("32-digit trace_id, span_id and sample, no parent_id", function()
      local b3 = fmt("%s-%s-%s", trace_id_32, span_id, "1")
      local t = { parse_http_req_headers({ b3 = b3 }) }
      assert.same({ trace_id_32, span_id, nil, true }, to_hex_first_3(t))
      assert.spy(warn).not_called()
    end)

    it("sample debug = always sample", function()
      local b3 = fmt("%s-%s-%s-%s", trace_id, span_id, "d", parent_id)
      local t  = { parse_http_req_headers({ b3 = b3 }) }
      assert.same({ trace_id, span_id, parent_id, true }, to_hex_first_3(t))
      assert.spy(warn).not_called()
    end)

    it("sample 0 = don't sample", function()
      local b3 = fmt("%s-%s-%s-%s", trace_id, span_id, "0", parent_id)
      local t  = { parse_http_req_headers({ b3 = b3 }) }
      assert.same({ trace_id, span_id, parent_id, false }, to_hex_first_3(t))
      assert.spy(warn).not_called()
    end)

    it("sample 0 overriden by x-b3-sampled", function()
      local b3 = fmt("%s-%s-%s-%s", trace_id, span_id, "0", parent_id)
      local t  = { parse_http_req_headers({ b3 = b3, ["x-b3-sampled"] = "1" }) }
      assert.same({ trace_id, span_id, parent_id, true }, to_hex_first_3(t))
      assert.spy(warn).not_called()
    end)

    describe("errors", function()
      it("requires trace id", function()
        local t = { parse_http_req_headers({ b3 = "" }) }
        assert.same({}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")
      end)

      it("rejects existing but invalid trace_id", function()
        local t = { parse_http_req_headers({ b3 = non_hex_id .. "-" .. span_id }) }
        assert.same({}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")

        t = { parse_http_req_headers({ b3 = too_short_id .. "-" .. span_id }) }
        assert.same({}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")

        -- too long
        t = { parse_http_req_headers({ b3 = too_long_id .. "-" .. span_id }) }
        assert.same({}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")
      end)

      it("requires span_id", function()
        local t = { parse_http_req_headers({ b3 = trace_id .. "-" }) }
        assert.same({}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")
      end)

      it("rejects existing but invalid span_id", function()
        local t = { parse_http_req_headers({ b3 = trace_id .. non_hex_id }) }
        assert.same({}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")

        t = { parse_http_req_headers({ b3 = trace_id .. too_short_id }) }
        assert.same({}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")

        t = { parse_http_req_headers({ b3 = trace_id .. too_long_id }) }
        assert.same({}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")
      end)

      it("rejects invalid sampled section", function()
        local b3 = fmt("%s-%s-%s-%s", trace_id, span_id, "x", parent_id)
        local t  = { parse_http_req_headers({ b3 = b3 }) }
        assert.same({}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")
      end)

      it("rejects invalid parent_id section", function()
        local b3 = fmt("%s-%s-%s-%s", trace_id, span_id, "d", non_hex_id)
        local t  = { parse_http_req_headers({ b3 = b3 }) }
        assert.same({}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")

        b3 = fmt("%s-%s-%s-%s", trace_id, span_id, "d", too_short_id)
        t  = { parse_http_req_headers({ b3 = b3 }) }
        assert.same({}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")

        b3 = fmt("%s-%s-%s-%s", trace_id, span_id, "d", too_long_id)
        t  = { parse_http_req_headers({ b3 = b3 }) }
        assert.same({}, t)
        assert.spy(warn).called_with("b3 single header invalid; ignoring.")
      end)
    end)
  end)

  describe("W3C header parsing", function()
    local warn
    before_each(function()
      warn = spy.on(kong.log, "warn")
    end)

    it("valid traceparent with sampling", function()
      local traceparent = fmt("00-%s-%s-01", trace_id_32, parent_id)
      local t = { parse_http_req_headers({ traceparent = traceparent }) }
      assert.same({ trace_id_32, nil, parent_id, true }, to_hex_first_3(t))
      assert.spy(warn).not_called()
    end)

    it("valid traceparent without sampling", function()
      local traceparent = fmt("00-%s-%s-00", trace_id_32, parent_id)
      local t = { parse_http_req_headers({ traceparent = traceparent }) }
      assert.same({ trace_id_32, nil, parent_id, false }, to_hex_first_3(t))
      assert.spy(warn).not_called()
    end)

    it("sampling with mask", function()
      local traceparent = fmt("00-%s-%s-09", trace_id_32, parent_id)
      local t = { parse_http_req_headers({ traceparent = traceparent }) }
      assert.same(true, t[4])
      assert.spy(warn).not_called()
    end)

    it("no sampling with mask", function()
      local traceparent = fmt("00-%s-%s-08", trace_id_32, parent_id)
      local t = { parse_http_req_headers({ traceparent = traceparent }) }
      assert.same(false, t[4])
      assert.spy(warn).not_called()
    end)

    describe("errors", function()
      it("rejects W3C versions other than 00", function()
        local traceparent = fmt("01-%s-%s-00", trace_id_32, parent_id)
        local t = { parse_http_req_headers({ traceparent = traceparent }) }
        assert.same({}, t)
        assert.spy(warn).was_called_with("invalid W3C Trace Context version; ignoring.")
      end)

      it("rejects invalid header", function()
        local traceparent = "vv-00000000000000000000000000000001-0000000000000001-00"
        local t = { parse_http_req_headers({ traceparent = traceparent }) }
        assert.same({}, t)
        assert.spy(warn).was_called_with("invalid W3C traceparent header; ignoring.")

        traceparent = "00-vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv-0000000000000001-00"
        t = { parse_http_req_headers({ traceparent = traceparent }) }
        assert.same({}, t)
        assert.spy(warn).was_called_with("invalid W3C traceparent header; ignoring.")

        traceparent = "00-00000000000000000000000000000001-vvvvvvvvvvvvvvvv-00"
        t = { parse_http_req_headers({ traceparent = traceparent }) }
        assert.same({}, t)
        assert.spy(warn).was_called_with("invalid W3C traceparent header; ignoring.")

        traceparent = "00-00000000000000000000000000000001-0000000000000001-vv"
        t = { parse_http_req_headers({ traceparent = traceparent }) }
        assert.same({}, t)
        assert.spy(warn).was_called_with("invalid W3C traceparent header; ignoring.")
      end)

      it("rejects invalid trace IDs", function()
        local traceparent = fmt("00-%s-%s-00", too_short_id, parent_id)
        local t = { parse_http_req_headers({ traceparent = traceparent }) }
        assert.same({}, t)
        assert.spy(warn).was_called_with("invalid W3C trace context trace ID; ignoring.")

        traceparent = fmt("00-%s-%s-00", too_long_id, parent_id)
        t = { parse_http_req_headers({ traceparent = traceparent }) }
        assert.same({}, t)
        assert.spy(warn).was_called_with("invalid W3C trace context trace ID; ignoring.")

        -- cannot be all zeros
        traceparent = fmt("00-00000000000000000000000000000000-%s-00", too_long_id, parent_id)
        t = { parse_http_req_headers({ traceparent = traceparent }) }
        assert.same({}, t)
        assert.spy(warn).was_called_with("invalid W3C trace context trace ID; ignoring.")
      end)

      it("rejects invalid parent IDs", function()
        local traceparent = fmt("00-%s-%s-00", trace_id_32, too_short_id)
        local t = { parse_http_req_headers({ traceparent = traceparent }) }
        assert.same({}, t)
        assert.spy(warn).was_called_with("invalid W3C trace context parent ID; ignoring.")

        traceparent = fmt("00-%s-%s-00", trace_id_32, too_long_id)
        t = { parse_http_req_headers({ traceparent = traceparent }) }
        assert.same({}, t)
        assert.spy(warn).was_called_with("invalid W3C trace context parent ID; ignoring.")

        -- cannot be all zeros
        traceparent = fmt("00-%s-0000000000000000-01", trace_id_32)
        t = { parse_http_req_headers({ traceparent = traceparent }) }
        assert.same({}, t)
        assert.spy(warn).was_called_with("invalid W3C trace context parent ID; ignoring.")
      end)

      it("rejects invalid trace flags", function()
        local traceparent = fmt("00-%s-%s-000", trace_id_32, parent_id)
        local t = { parse_http_req_headers({ traceparent = traceparent }) }
        assert.same({}, t)
        assert.spy(warn).was_called_with("invalid W3C trace context flags; ignoring.")

        traceparent = fmt("00-%s-%s-0", trace_id_32, parent_id)
        t = { parse_http_req_headers({ traceparent = traceparent }) }
        assert.same({}, t)
        assert.spy(warn).was_called_with("invalid W3C trace context flags; ignoring.")
      end)
    end)
  end)
end)
