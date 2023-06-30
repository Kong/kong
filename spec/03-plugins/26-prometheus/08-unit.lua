
describe("Plugin: prometheus (unit)",function()
  local prometheus

  setup(function()
    package.loaded['prometheus_resty_counter'] = require("resty.counter")

    ngx.shared = require("spec.fixtures.shm-stub")
    ngx.get_phase = function()
      return "init_worker"
    end

    prometheus = require("kong.plugins.prometheus.prometheus")
  end)

  it("check metric names", function()
    local prom = prometheus.init("prometheus_metrics", "kong_")

    local m = prom:counter("mem_used")
    assert.truthy(m)

    m = prom:counter("Mem_Used")
    assert.truthy(m)

    m = prom:counter(":mem_used")
    assert.truthy(m)

    m = prom:counter("mem_used:")
    assert.truthy(m)

    m = prom:counter("_mem_used_")
    assert.truthy(m)

    m = prom:counter("mem-used")
    assert.falsy(m)

    m = prom:counter("0name")
    assert.falsy(m)

    m = prom:counter("name$")
    assert.falsy(m)
  end)
end)
