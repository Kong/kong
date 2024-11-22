-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local utils = require "kong.enterprise_edition.debug_session.utils"
local helpers = require "spec.helpers"

describe("Debug Session IO Instrumentation", function()
  local instrum, tracer

  lazy_setup(function()
    package.loaded["kong.enterprise_edition.debug_session.instrumentation.init"] = nil
    package.loaded["kong.enterprise_edition.debug_session.instrumentation.socket"] = nil
    package.loaded["kong.enterprise_edition.debug_session.instrumentation.redis"] = nil

    instrum = {}
    tracer = {}

    spy.on(tracer, "start_span")
    spy.on(instrum, "is_valid_phase")
    stub(instrum, "INSTRUMENTATIONS")
    stub(instrum, "should_skip_instrumentation").returns(false)
  end)

  describe("Redis", function()
    local redis, redis_instrum_mod
    local REDIS_TOTAL_TIME_CTX_KEY = utils.get_ctx_key("redis_total_time")

    lazy_setup(function()
      redis = require "kong.enterprise_edition.tools.redis.v2"
      redis_instrum_mod = require "kong.enterprise_edition.debug_session.instrumentation.redis"
      redis_instrum_mod.instrument()
      redis_instrum_mod.init({ tracer = tracer, instrum =  instrum })
    end)

    before_each(function()
      tracer.start_span:clear()
      instrum.should_skip_instrumentation:clear()
      instrum.is_valid_phase:clear()
    end)

    it("get_total_time", function()
      ngx.ctx[REDIS_TOTAL_TIME_CTX_KEY] = 1000000
      assert.equals(1, redis_instrum_mod.get_total_time())
    end)

    it("does not execute patched code if outside of a request context", function()
      local red = redis.connection({
        host = helpers.redis_host,
        port = helpers.redis_port,
      })
      red:set("foo", "bar")

      assert.spy(instrum.is_valid_phase).was_called()
      assert.stub(instrum.should_skip_instrumentation).was_not_called()
      assert.spy(tracer.start_span).was_not_called()
    end)
  end)

  describe("Socket", function()
    local socket_instrum_mod, dynamic_hook
    local SOCKET_TOTAL_TIME_CTX_KEY = utils.get_ctx_key("socket_total_time")

    lazy_setup(function()
      dynamic_hook = require "kong.dynamic_hook"
      socket_instrum_mod = require "kong.enterprise_edition.debug_session.instrumentation.socket"
      socket_instrum_mod.instrument()
      socket_instrum_mod.init({ tracer = tracer, instrum = instrum })
    end)

    before_each(function()
      tracer.start_span:clear()
      instrum.should_skip_instrumentation:clear()
      instrum.is_valid_phase:clear()

      -- request scoped dynamic hooks don't work in timers
      dynamic_hook.enable_by_default("active-tracing")
    end)

    lazy_teardown(function()
      dynamic_hook.disable_by_default("active-tracing")
    end)

    it("get_total_time", function()
      ngx.ctx[SOCKET_TOTAL_TIME_CTX_KEY] = 2000000
      assert.equals(2, socket_instrum_mod.get_total_time())
    end)

    it("does not execute patched code if outside of a request context", function()
      local sock = ngx.socket.tcp()
      sock:connect("localhost", 4242)
      sock:send("foo")
      sock:receive("*a")
      sock:close()

      assert.spy(instrum.is_valid_phase).was_called(3)
      assert.stub(instrum.should_skip_instrumentation).was_not_called()
      assert.spy(tracer.start_span).was_not_called()
    end)
  end)
end)
