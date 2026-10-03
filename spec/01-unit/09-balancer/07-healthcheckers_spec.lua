-- Tests for the grpc/grpcs -> http/https type remapping in create_healthchecker.
-- All Kong infrastructure is stubbed so these tests run with plain busted.

local captured_opts

-- Stub transitive dependencies before requiring the module under test.
package.preload["kong.runloop.balancer.balancers"] = function()
  return { get_upstream = function() end }
end
package.preload["kong.runloop.balancer.upstreams"] = function()
  return {
    get_upstream_by_id = function() end,
    get_all_upstreams = function() return {} end,
  }
end
package.preload["kong.runloop.certificate"] = function()
  return { get_certificate = function() return nil, "no-cert" end }
end

local healthcheckers = require "kong.runloop.balancer.healthcheckers"


local function make_upstream(active_type, passive_type)
  return {
    ws_id              = "test-ws-id",
    name               = "test-upstream",
    client_certificate = nil,
    host_header        = nil,
    healthchecks = {
      active = {
        type        = active_type or "http",
        http_path   = "/",
        timeout     = 1,
        concurrency = 10,
        https_verify_certificate = true,
        healthy   = { interval = 1, http_statuses = { 200 }, successes = 1 },
        unhealthy = {
          interval      = 1,
          http_statuses = { 500 },
          tcp_failures  = 1,
          timeouts      = 1,
          http_failures = 1,
        },
      },
      passive = {
        type    = passive_type or "http",
        healthy = { http_statuses = { 200 }, successes = 0 },
        unhealthy = {
          http_statuses = { 429, 500 },
          tcp_failures  = 1,
          timeouts      = 1,
          http_failures = 1,
        },
      },
    },
  }
end


local function make_balancer()
  return {
    eachAddress = function(self, fn) end,
    setCallback = function() end,
  }
end


describe("healthcheckers.create_healthchecker()", function()

  before_each(function()
    captured_opts = nil

    package.loaded["resty.healthcheck"] = {
      new = function(opts)
        captured_opts = opts
        return {
          add_target        = function() return true end,
          get_target_status = function() return nil end,
          events            = { healthy = "healthy", unhealthy = "unhealthy" },
          EVENT_SOURCE      = "hc-test",
          stop              = function() end,
          clear             = function() return true end,
        }
      end,
    }

    _G.ngx        = _G.ngx or {}
    _G.ngx.log    = function() end
    _G.ngx.ERR    = 4
    _G.ngx.WARN   = 5
    _G.ngx.config = { subsystem = "http" }

    _G.kong = {
      worker_events = {
        register_weak = function() end,
        unregister    = function() end,
      },
      configuration = { client_ssl = false },
    }

    healthcheckers.init()
  end)

  -- grpc type remapping -----------------------------------------------

  it("remaps active.type grpc -> http before calling healthcheck.new", function()
    local upstream = make_upstream("grpc", "http")
    local ok, err = healthcheckers.create_healthchecker(make_balancer(), upstream)

    assert.is_nil(err)
    assert.is_truthy(ok)
    assert.is_not_nil(captured_opts)
    assert.equals("http", captured_opts.checks.active.type)
  end)

  it("remaps active.type grpcs -> https before calling healthcheck.new", function()
    local upstream = make_upstream("grpcs", "http")
    local ok, err = healthcheckers.create_healthchecker(make_balancer(), upstream)

    assert.is_nil(err)
    assert.is_truthy(ok)
    assert.is_not_nil(captured_opts)
    assert.equals("https", captured_opts.checks.active.type)
  end)

  it("remaps passive.type grpc -> http before calling healthcheck.new", function()
    local upstream = make_upstream("http", "grpc")
    healthcheckers.create_healthchecker(make_balancer(), upstream)

    assert.is_not_nil(captured_opts)
    assert.equals("http", captured_opts.checks.passive.type)
  end)

  it("remaps passive.type grpcs -> https before calling healthcheck.new", function()
    local upstream = make_upstream("http", "grpcs")
    healthcheckers.create_healthchecker(make_balancer(), upstream)

    assert.is_not_nil(captured_opts)
    assert.equals("https", captured_opts.checks.passive.type)
  end)

  -- Non-grpc types pass through unchanged -----------------------------

  it("leaves active.type http unchanged", function()
    local upstream = make_upstream("http", "http")
    healthcheckers.create_healthchecker(make_balancer(), upstream)

    assert.is_not_nil(captured_opts)
    assert.equals("http", captured_opts.checks.active.type)
  end)

  it("leaves active.type https unchanged", function()
    local upstream = make_upstream("https", "http")
    healthcheckers.create_healthchecker(make_balancer(), upstream)

    assert.is_not_nil(captured_opts)
    assert.equals("https", captured_opts.checks.active.type)
  end)

  it("leaves active.type tcp unchanged", function()
    local upstream = make_upstream("tcp", "http")
    -- tcp in http subsystem zeros the active intervals; keep passive
    -- thresholds non-zero so the healthchecker path is still taken.
    upstream.healthchecks.passive.unhealthy.tcp_failures = 1
    healthcheckers.create_healthchecker(make_balancer(), upstream)

    assert.is_not_nil(captured_opts)
    assert.equals("tcp", captured_opts.checks.active.type)
  end)

  -- Original upstream table must not be mutated ----------------------

  it("does not mutate upstream.healthchecks when active.type is grpc", function()
    local upstream = make_upstream("grpc", "http")
    healthcheckers.create_healthchecker(make_balancer(), upstream)

    assert.equals("grpc", upstream.healthchecks.active.type)
  end)

  it("does not mutate upstream.healthchecks when passive.type is grpcs", function()
    local upstream = make_upstream("http", "grpcs")
    healthcheckers.create_healthchecker(make_balancer(), upstream)

    assert.equals("grpcs", upstream.healthchecks.passive.type)
  end)

  -- Stream-subsystem gating still correct for grpc -------------------

  it("zeros active intervals and remaps grpc type in stream subsystem", function()
    _G.ngx.config.subsystem = "stream"
    local upstream = make_upstream("grpc", "http")
    healthcheckers.create_healthchecker(make_balancer(), upstream)

    assert.is_not_nil(captured_opts)
    assert.equals("http", captured_opts.checks.active.type)
    assert.equals(0, captured_opts.checks.active.healthy.interval)
    assert.equals(0, captured_opts.checks.active.unhealthy.interval)
  end)
end)
