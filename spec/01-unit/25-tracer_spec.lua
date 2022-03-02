local helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"
local inspect = require 'inspect'

describe("Tracer PDK", function()
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
  end)

  it("init tracer", function()
    assert(tracer_mod.new(), "failed to init tracer")
  end)

  -- TODO: multiple tracer test
  it("multiple tracer", function()
    assert(tracer_mod.new("core"), "failed to init tracer")
  end)

  it("start and end span", function()
    local span = assert(tracer_global:start_span(ngx.ctx, "test"))
    assert.is_same(true, span.is_recording)
    assert(span:finish())
    assert.is_same(false, span.is_recording)
  end)

  it("sub spans", function()
    local span = assert(tracer_global:start_span(ngx.ctx, "test"))
    assert.is_same(true, span.is_recording)
    assert(span:finish())
    assert.is_same(false, span.is_recording)
  end)

end)
