local load_pb = require("kong.plugins.opentelemetry.otlp").load_pb
local to_pb = require("kong.plugins.opentelemetry.otlp").to_pb
local to_otlp_span = require("kong.plugins.opentelemetry.otlp").to_otlp_span
local otlp_export_request = require("kong.plugins.opentelemetry.otlp").otlp_export_request
local helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"
local inspect = require 'inspect'
local pb = require "pb"

describe("otlp", function()
  local tracer_mod
  local tracer_global

  lazy_setup(function()
    local conf = assert(conf_loader(nil, {
      plugins = "bundled",
    }))

    local kong_global = require "kong.global"
    _G.kong = kong_global.new()
    kong_global.init_pdk(kong, conf, nil)
    tracer_mod = require("kong.pdk.tracer")
    tracer_global = kong.tracer.new("test", {
      sample_ratio = 1,
    })

    load_pb()
  end)

  it("to_otlp_span spec", function ()
    local span = assert(kong.tracer:start_span(ngx.ctx, "test"))
    span:finish()

    assert(to_otlp_span(span))
  end)

  it("otlp_export_request spec", function ()
    local span = assert(kong.tracer:start_span(ngx.ctx, "test"))
    span:finish()

    local req = assert(otlp_export_request({ span }))
    ngx.say(inspect(req))
  end)

  it("to_pb", function ()
    local span = assert(kong.tracer:start_span(ngx.ctx, "test"))
    span:finish()

    local req = assert(otlp_export_request({ span }))
    local pb_bytes = assert(to_pb(req))
    print(pb.tohex(pb_bytes))

    local decoded = assert(pb.decode("ExportTraceServiceRequest", pb_bytes))
    print(inspect(decoded))
  end)

end)
