local new_zipkin_reporter = require("kong.plugins.zipkin.reporter").new
local new_span = require("kong.plugins.zipkin.span").new
local utils = require "kong.tools.utils"
local to_hex = require "resty.string".to_hex


local function gen_trace_id(traceid_byte_count)
  return to_hex(utils.get_rand_bytes(traceid_byte_count))
end

local function gen_span_id()
  return to_hex(utils.get_rand_bytes(8))
end

describe("reporter", function ()
  it("constructs a reporter", function ()
    local reporter = new_zipkin_reporter("http://localhost:1234", "DefaultServiceName", "LocalServiceName")
    assert.same(reporter.default_service_name, "DefaultServiceName")
    assert.same(reporter.local_service_name, "LocalServiceName")
  end)

  it("pushes spans into the pending spans buffer", function ()
    local reporter = new_zipkin_reporter("http://localhost:1234", "DefaultServiceName", "LocalServiceName")
    local span = new_span(
      "SERVER",
      "test-span",
      1,
      true,
      gen_trace_id(16),
      gen_span_id(),
      gen_span_id(),
      {}
    )
    reporter:report(span)
    assert(reporter.pending_spans_n, 1)
    assert.same(reporter.pending_spans, {
      {
        id = to_hex(span.span_id),
        name = "test-span",
        kind = "SERVER",
        localEndpoint = { serviceName = "LocalServiceName" },
        remoteEndpoint = { serviceName = "DefaultServiceName" },
        timestamp = 1,
        traceId = to_hex(span.trace_id),
        parentId = to_hex(span.parent_id),
      }
    })
  end)
end)
