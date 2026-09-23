
describe("Plugin: prometheus (unit)", function()
  local prometheus

  local orig_ngx_shared    = ngx.shared
  local orig_ngx_get_phase = ngx.get_phase
  local orig_ngx_timer     = ngx.timer

  setup(function()
    ngx.shared = require("spec.fixtures.shm-stub")
    ngx.get_phase = function()  -- luacheck: ignore
      return "init_worker"
    end
    ngx.timer = {               -- luacheck: ignore
      every = function() end,
    }

    package.loaded['prometheus_resty_counter'] = require("resty.counter")
    prometheus = require("kong.plugins.prometheus.prometheus")
  end)

  teardown(function()
    ngx.shared    = orig_ngx_shared
    ngx.get_phase = orig_ngx_get_phase  -- luacheck: ignore
    ngx.timer     = orig_ngx_timer      -- luacheck: ignore
  end)

  it("check metric names", function()
    local prom = prometheus.init("prometheus_metrics", "kong_")
    local m

    m = prom:counter("mem_used")
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

  it("check metric label names", function()
    local prom = prometheus.init("prometheus_metrics", "kong_")
    local m

    m = prom:counter("mem0", nil, {"LUA"})
    assert.truthy(m)

    m = prom:counter("mem1", nil, {"lua"})
    assert.truthy(m)

    m = prom:counter("mem2", nil, {"_lua_"})
    assert.truthy(m)

    m = prom:counter("mem3", nil, {":lua"})
    assert.falsy(m)

    m = prom:counter("mem4", nil, {"0lua"})
    assert.falsy(m)

    m = prom:counter("mem5", nil, {"lua*"})
    assert.falsy(m)

    m = prom:counter("mem6", nil, {"lua\\5.1"})
    assert.falsy(m)

    m = prom:counter("mem7", nil, {"lua\"5.1\""})
    assert.falsy(m)

    m = prom:counter("mem8", nil, {"lua-vm"})
    assert.falsy(m)
  end)

  it("check metric full name", function()
    local prom = prometheus.init("prometheus_metrics", "kong_")
    local shm = ngx.shared["prometheus_metrics"]
    local m

    m = prom:counter("mem", nil, {"lua"})
    assert.truthy(m)
    m:inc(1, {"2.1"})

    m = prom:counter("file", nil, {"path"})
    assert.truthy(m)
    m:inc(1, {"\\root"})

    m = prom:counter("user", nil, {"name"})
    assert.truthy(m)
    m:inc(1, {"\"quote"})

    -- sync to shdict
    prom._counter:sync()

    assert.equal(shm:get([[mem{lua="2.1"}]]), 1)
    assert.equal(shm:get([[file{path="\\root"}]]), 1)
    assert.equal(shm:get([[user{name="\"quote"}]]), 1)
  end)

  it("emit metric data", function()
    local prom = prometheus.init("metrics", "kong_")
    local m

    m = prom:counter("mem", nil, {"lua"})
    assert.truthy(m)
    m:inc(2, {"2.1"})

    m = prom:counter("file", nil, {"path"})
    assert.truthy(m)
    m:inc(3, {"\\root"})

    m = prom:counter("user", nil, {"name"})
    assert.truthy(m)
    m:inc(5, {"\"quote"})
    m:inc(1, {"\"quote"})

    local str = ""
    prom:metric_data(function(d)
      str = str .. d
    end)

    assert.truthy(str:find([[kong_mem{lua="2.1"} 2]], 1, true))
    assert.truthy(str:find([[kong_file{path="\\root"} 3]], 1, true))
    assert.truthy(str:find([[kong_user{name="\"quote"} 6]], 1, true))
  end)

end)
