-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local debug_instrumentation = require "kong.enterprise_edition.debug_session.instrumentation"
local utils = require "kong.enterprise_edition.debug_session.utils"

local log = utils.log
local ngx_ERR = ngx.ERR
local ngx_DEBUG = ngx.DEBUG

local function init(start_callback, stop_callback)
  local function enable_instrumentation()
    log(ngx_DEBUG, "enabling instrumentation")

    debug_instrumentation.set({ "all" }, {
      tracing_sampling_rate = 1,
    })
  end

  local function disable_instrumentation()
    log(ngx_DEBUG, "disabling instrumentation")
    debug_instrumentation.set({ "off" })
  end

  local function enable_sampler()
    log(ngx_DEBUG, "enabling sampler")
    local sampling_rule = kong.debug_session.context:get_sampling_rule()
    if sampling_rule ~= "" then
      kong.debug_session.sampler:add_matcher(sampling_rule)
    end
  end

  local function disable_sampler()
    log(ngx_DEBUG, "disabling sampler")
    kong.debug_session.sampler:remove_matcher()
  end

  local function init_session(session_id)
    kong.debug_session:init_session(session_id)
  end

  local function end_session(session_id)
    kong.debug_session:end_session(session_id)
  end

  kong.worker_events.register(function(data)
    if not data or not data.session_id then
      log(ngx_ERR, "invalid data")
      return
    end

    if start_callback then
      start_callback()
    end

    -- enabled ngx.socket hooks
    local dynamic_hook = require "kong.dynamic_hook"
    dynamic_hook.enable_by_default("active-tracing")
    init_session(data.session_id)
    enable_instrumentation()
    enable_sampler()
  end, "debug_session", "start")

  kong.worker_events.register(function(data)
    if not data or not data.session_id then
      log(ngx_ERR, "invalid data")
      return
    end

    if stop_callback then
      stop_callback()
    end
    local dynamic_hook = require "kong.dynamic_hook"
    dynamic_hook.disable_by_default("active-tracing")
    end_session(data.session_id)
    disable_instrumentation()
    disable_sampler()
  end, "debug_session", "stop")
end

local function start(session_id)
  kong.worker_events.post("debug_session", "start", {
    session_id = session_id
  })
end

local function stop(session_id)
  kong.worker_events.post("debug_session", "stop", {
    session_id = session_id
  })
end


return {
  init = init,
  start = start,
  stop = stop,
}
