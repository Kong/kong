local propagation_utils = require "kong.observability.tracing.propagation.utils"
local tablex = require "pl.tablex"
local shallow_copy = require "kong.tools.table".shallow_copy
local to_hex = require "resty.string".to_hex

local from_hex = propagation_utils.from_hex
local fmt = string.format


-- W3C Ids
local trace_id_16_w3c    = "0af7651916cd43dd8448eb211c80319c"
local trace_id_8_w3c_dec = "9532127138774266268"  -- 8448eb211c80319c to decimal
local span_id_8_w3c      = "b7ad6b7169203331"
local span_id_8_w3c_dec  = "13235353014750950193" -- b7ad6b7169203331 to decimal

-- B3 Ids
local trace_id_16_b3     = "dc9d1b0ccedf0ecaf4f26ffab84d4f5e"
local trace_id_8_b3      = "f4f26ffab84d4f5e"
local span_id_8_b3       = "b7ad6b7169203332"
local span_id_8_b3p      = "f4f26ffab84d4f5f"

-- Jaeger Ids
local trace_id_16_jae    = "f744b23fe9aa64f08255043ba51848db"
local span_id_8_jae      = "f4f26ffab84d4f60"
local span_id_8_jaep     = "f4f26ffab84d4f61"

local padding_prefix     = string.rep("0", 16)

-- apply some transformation to a hex id (affects last byte)
local function transform_hex_id(id)
  local max = string.byte("f")
  local min = string.byte("0")

  local bytes = { id:byte(1, -1) }
  local last_byte = bytes[#bytes]

  last_byte = last_byte + 1 < max and last_byte + 1 or min
  bytes[#bytes] = last_byte
  return string.char(unpack(bytes))
end

-- apply some transformation (same as transform_hex_id above) to a binary id
local function transform_bin_id(bid)
  return from_hex(transform_hex_id(to_hex(bid)))
end

local request_headers_1 = {
  traceparent = fmt("00-%s-%s-01", trace_id_16_w3c, span_id_8_w3c),
  ["x-b3-traceid"] = trace_id_16_b3,
  ["x-b3-spanid"] = span_id_8_b3,
  ["x-b3-sampled"] = "1",
  ["x-b3-parentspanid"] = span_id_8_b3p,
  ["uber-trace-id"] = fmt("%s:%s:%s:%s", trace_id_16_jae, span_id_8_jae, span_id_8_jaep, "01"),
}

local request_headers_2 = {
  ["x-b3-traceid"] = trace_id_8_b3,
  ["x-b3-spanid"] = span_id_8_b3,
  ["x-b3-sampled"] = "1",
  ["x-b3-parentspanid"] = span_id_8_b3p,
}


local test_data = { {
  description = "extract empty, inject empty (propagation disabled)",
  req_headers = request_headers_1,
  conf = {
    propagation = {
      extract = {},
      inject = {},
    }
  },
  expected = request_headers_1
}, {
  description = "extract = ignore, inject single heder",
  req_headers = request_headers_1,
  conf = {
    propagation = {
      extract = {},
      inject = { "w3c" },
    }
  },
  cb = function()
    -- no extraction, set some values using the callback
    -- (same as what tracing plugins would do)
    return {
      trace_id = from_hex("0af7651916cd43dd8448eb211c80319d"),
      span_id = from_hex("8448eb211c80319e"),
      should_sample = true,
    }
  end,
  expected = tablex.merge(request_headers_1, {
    traceparent = fmt("00-%s-%s-01", "0af7651916cd43dd8448eb211c80319d", "8448eb211c80319e"),
  }, true)
}, {
  description = "extract = ignore, inject multiple heders",
  req_headers = request_headers_1,
  conf = {
    propagation = {
      extract = {},
      inject = { "w3c", "b3-single" },
    }
  },
  cb = function()
    -- no extraction, set some values using the callback
    -- (same as what tracing plugins would do)
    return {
      trace_id = from_hex("0af7651916cd43dd8448eb211c80319d"),
      span_id = from_hex("8448eb211c80319e"),
      should_sample = true,
    }
  end,
  expected = tablex.merge(request_headers_1, {
    traceparent = fmt("00-%s-%s-01", "0af7651916cd43dd8448eb211c80319d", "8448eb211c80319e"),
    b3 = fmt("%s-%s-1", "0af7651916cd43dd8448eb211c80319d", "8448eb211c80319e"),
  }, true)
}, {
  description = "extract = ignore, inject = preserve, no default setting",
  req_headers = request_headers_1,
  conf = {
    propagation = {
      extract = {},
      inject = { "preserve" },
    }
  },
  cb = function()
    -- no extraction, set some values using the callback
    -- (same as what tracing plugins would do)
    return {
      trace_id = from_hex("0af7651916cd43dd8448eb211c80319d"),
      span_id = from_hex("8448eb211c80319e"),
      should_sample = true,
    }
  end,
  expected = tablex.merge(request_headers_1, {
    traceparent = fmt("00-%s-%s-01", "0af7651916cd43dd8448eb211c80319d", "8448eb211c80319e"),
  }, true)
}, {
  description = "extract = ignore, inject = preserve, uses default format",
  req_headers = request_headers_1,
  conf = {
    propagation = {
      extract = {},
      inject = { "preserve" },
      default_format = "datadog",
    }
  },
  cb = function()
    -- no extraction, set some values using the callback
    -- (same as what tracing plugins would do)
    return {
      trace_id = from_hex("0af7651916cd43dd8448eb211c80319d"),
      span_id = from_hex("8448eb211c80319e"),
      should_sample = true,
    }
  end,
  expected = tablex.merge(request_headers_1, {
    ["x-datadog-trace-id"] = "9532127138774266269",    -- 8448eb211c80319d to dec
    ["x-datadog-parent-id"] = "9532127138774266270",   -- 8448eb211c80319e to dec
    ["x-datadog-sampling-priority"] = "1"
  }, true)
}, {
  description = "extract configured with header not found in request, inject = preserve, uses default format",
  req_headers = request_headers_1,
  conf = {
    propagation = {
      extract = { "datadog" },
      inject = { "preserve" },
      default_format = "ot"
    }
  },
  -- apply some updates to the extracted ctx
  cb = function(ctx)
    assert.same(ctx, {})

    ctx.trace_id = from_hex("0af7651916cd43dd8448eb211c80319d")
    ctx.span_id = from_hex("8448eb211c80319e")
    ctx.should_sample = true

    return ctx
  end,
  expected = tablex.merge(request_headers_1, {
    ["ot-tracer-sampled"] = '1',
    ["ot-tracer-spanid"] = '8448eb211c80319e',
    ["ot-tracer-traceid"] = '8448eb211c80319d',
  }, true)
}, {
  description = "extract configured with header found in request, inject = preserve + other formats",
  req_headers = request_headers_1,
  conf = {
    propagation = {
      extract = { "b3", "w3c", "jaeger" },
      inject = { "w3c", "preserve", "b3-single" },
    }
  },
  -- apply some updates to the extracted ctx
  cb = function(ctx)
    ctx.trace_id = transform_bin_id(ctx.trace_id)
    ctx.span_id = transform_bin_id(ctx.span_id)
    ctx.parent_id = transform_bin_id(ctx.parent_id)
    return ctx
  end,
  expected = tablex.merge(request_headers_1, {
    traceparent = fmt("00-%s-%s-01", transform_hex_id(trace_id_16_b3), transform_hex_id(span_id_8_b3)),
    ["x-b3-traceid"] = transform_hex_id(trace_id_16_b3),
    ["x-b3-spanid"] = transform_hex_id(span_id_8_b3),
    ["x-b3-sampled"] = "1",
    ["x-b3-parentspanid"] = transform_hex_id(span_id_8_b3p),
    b3 = fmt("%s-%s-1-%s", transform_hex_id(trace_id_16_b3), transform_hex_id(span_id_8_b3),
      transform_hex_id(span_id_8_b3p)),
  }, true)
}, {
  description = "extract configured with header formats, injection disabled",
  req_headers = request_headers_1,
  conf = {
    propagation = {
      extract = { "gcp", "aws", "ot", "datadog", "b3", "w3c", "jaeger" },
      inject = {},
    }
  },
  cb = function()
    return {
      trace_id = from_hex("abcdef"),
      span_id = from_hex("123fff"),
      should_sample = true,
    }
  end,
  expected = request_headers_1
}, {
  description = "extract configured with header formats, b3 first",
  req_headers = request_headers_1,
  conf = {
    propagation = {
      extract = { "b3", "w3c", "jaeger" },
      inject = { "w3c" },
    }
  },
  -- apply some updates to the extracted ctx
  cb = function(ctx)
    ctx.trace_id = transform_bin_id(ctx.trace_id)
    ctx.span_id = transform_bin_id(ctx.span_id)
    return ctx
  end,
  expected = tablex.merge(request_headers_1, {
    traceparent = fmt("00-%s-%s-01", transform_hex_id(trace_id_16_b3), transform_hex_id(span_id_8_b3)),
  }, true)
}, {
  description = "extract configured with header formats, w3c first",
  req_headers = request_headers_1,
  conf = {
    propagation = {
      extract = { "w3c", "b3", "jaeger" },
      inject = { "w3c" },
    }
  },
  -- apply some updates to the extracted ctx
  cb = function(ctx)
    ctx.trace_id = transform_bin_id(ctx.trace_id)
    ctx.span_id = transform_bin_id(ctx.span_id)
    return ctx
  end,
  expected = tablex.merge(request_headers_1, {
    traceparent = fmt("00-%s-%s-01", transform_hex_id(trace_id_16_w3c), transform_hex_id(span_id_8_w3c)),
  }, true)
}, {
  description = "extract configured with header formats, missing first header",
  req_headers = request_headers_1,
  conf = {
    propagation = {
      extract = { "datadog", "jaeger", "b3" },
      inject = { "w3c" },
    }
  },
  -- apply some updates to the extracted ctx
  cb = function(ctx)
    ctx.trace_id = transform_bin_id(ctx.trace_id)
    ctx.span_id = transform_bin_id(ctx.span_id)
    return ctx
  end,
  expected = tablex.merge(request_headers_1, {
    traceparent = fmt("00-%s-%s-01", transform_hex_id(trace_id_16_jae), transform_hex_id(span_id_8_jae)),
  }, true)
}, {
  description = "extract configured with header formats, multiple injection",
  req_headers = request_headers_1,
  conf = {
    propagation = {
      extract = { "w3c", "b3", "jaeger" },
      inject = { "datadog", "w3c" },
    }
  },
  -- apply some updates to the extracted ctx
  cb = function(ctx)
    ctx.trace_id = transform_bin_id(ctx.trace_id)
    ctx.span_id = transform_bin_id(ctx.span_id)
    return ctx
  end,
  expected = tablex.merge(request_headers_1, {
    traceparent = fmt("00-%s-%s-01", transform_hex_id(trace_id_16_w3c), transform_hex_id(span_id_8_w3c)),
    ["x-datadog-trace-id"] = transform_hex_id(trace_id_8_w3c_dec),
    ["x-datadog-parent-id"] = transform_hex_id(span_id_8_w3c_dec),
    ["x-datadog-sampling-priority"] = "1"
  }, true)
}, {
  description = "extract = b3, 64b id, inject = b3 and w3c",
  req_headers = request_headers_2,
  conf = {
    propagation = {
      extract = { "b3", },
      inject = { "w3c", "b3" },
    }
  },
  -- apply some updates to the extracted ctx
  cb = function(ctx)
    ctx.trace_id = transform_bin_id(ctx.trace_id)
    ctx.span_id = transform_bin_id(ctx.span_id)
    ctx.parent_id = transform_bin_id(ctx.parent_id)
    return ctx
  end,
  expected = tablex.merge(request_headers_2, {
    traceparent = fmt("00-%s-%s-01", transform_hex_id(padding_prefix .. trace_id_8_b3), transform_hex_id(span_id_8_b3)),
    ["x-b3-traceid"] = transform_hex_id(trace_id_8_b3),   -- 64b (same as incoming)
    ["x-b3-spanid"] = transform_hex_id(span_id_8_b3),
    ["x-b3-sampled"] = "1",
    ["x-b3-parentspanid"] = transform_hex_id(span_id_8_b3p),
  }, true)
}, {
  description = "extract = b3, 128b id, inject = b3 and w3c",
  req_headers = request_headers_1,
  conf = {
    propagation = {
      extract = { "b3", },
      inject = { "w3c", "b3" },
    }
  },
  -- apply some updates to the extracted ctx
  cb = function(ctx)
    ctx.trace_id = transform_bin_id(ctx.trace_id)
    ctx.span_id = transform_bin_id(ctx.span_id)
    ctx.parent_id = transform_bin_id(ctx.parent_id)
    return ctx
  end,
  expected = tablex.merge(request_headers_1, {
    traceparent = fmt("00-%s-%s-01", transform_hex_id(trace_id_16_b3), transform_hex_id(span_id_8_b3)),
    ["x-b3-traceid"] = transform_hex_id(trace_id_16_b3),   -- 128b (same as incoming)
    ["x-b3-spanid"] = transform_hex_id(span_id_8_b3),
    ["x-b3-sampled"] = "1",
    ["x-b3-parentspanid"] = transform_hex_id(span_id_8_b3p),
  }, true)
}, {
  description = "extract configured with header formats, inject = preserve (matches jaeger)",
  req_headers = request_headers_1,
  conf = {
    propagation = {
      extract = { "datadog", "jaeger", "b3" },
      inject = { "preserve" },
    }
  },
  -- apply some updates to the extracted ctx
  cb = function(ctx)
    ctx.trace_id = transform_bin_id(ctx.trace_id)
    ctx.span_id = transform_bin_id(ctx.span_id)
    ctx.parent_id = transform_bin_id(ctx.parent_id)
    return ctx
  end,
  expected = tablex.merge(request_headers_1, {
    ["uber-trace-id"] = fmt("%s:%s:%s:%s", transform_hex_id(trace_id_16_jae), transform_hex_id(span_id_8_jae),
      transform_hex_id(span_id_8_jaep), "01"),
  }, true)
}, {
  description = "clear = b3 and w3c",
  req_headers = request_headers_1,
  conf = {
    propagation = {
      extract = { "datadog", "jaeger", "b3", "w3c" },
      inject = { "preserve" },
      clear = {
        "x-b3-traceid",
        "x-b3-spanid",
        "x-b3-sampled",
        "x-b3-parentspanid",
        "traceparent"
      }
    }
  },
  -- apply some updates to the extracted ctx
  cb = function(ctx)
    ctx.trace_id = transform_bin_id(ctx.trace_id)
    ctx.span_id = transform_bin_id(ctx.span_id)
    ctx.parent_id = transform_bin_id(ctx.parent_id)
    return ctx
  end,
  expected = {
    ["uber-trace-id"] = fmt("%s:%s:%s:%s", transform_hex_id(trace_id_16_jae), transform_hex_id(span_id_8_jae),
      transform_hex_id(span_id_8_jaep), "01"),
  }
} }



describe("Tracing Headers Propagation Module", function()
  local warn, err, set_serialize_value, req_headers
  local old_get_headers  = _G.ngx.req.get_headers
  local old_kong         = _G.kong

  _G.ngx.req.get_headers = function()
    return req_headers
  end

  _G.kong                = {
    ctx = {
      plugin = {},
    },
    log = {},
    service = {
      request = {
        set_header = function(name, value)
          req_headers[name] = value
        end,
        clear_header = function(name)
          req_headers[name] = nil
        end,
      }
    }
  }
  local propagation      = require "kong.observability.tracing.propagation"

  lazy_setup(function()
    err                 = spy.on(kong.log, "err")
    warn                = spy.on(kong.log, "warn")
    set_serialize_value = spy.on(kong.log, "set_serialize_value")
  end)

  lazy_teardown(function()
    _G.kong                = old_kong
    _G.ngx.req.get_headers = old_get_headers
  end)

  describe("propagate() function with", function()
    before_each(function()
      warn:clear()
      err:clear()
      set_serialize_value:clear()
    end)

    for _, t in ipairs(test_data) do
      it(t.description .. " updates headers correctly", function()
        local conf = t.conf
        local expected = t.expected
        req_headers = shallow_copy(t.req_headers)

        propagation.propagate(
          propagation.get_plugin_params(conf),
          t.cb or function(c) return c end
        )

        assert.spy(err).was_not_called()
        assert.spy(warn).was_not_called()
        assert.same(expected, req_headers)
      end)
    end
  end)
end)
