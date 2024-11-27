-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local sampler   = require "kong.enterprise_edition.debug_session.sampler"
local reporter  = require "kong.enterprise_edition.debug_session.reporter"
local context   = require "kong.enterprise_edition.debug_session.context"
local events    = require "kong.enterprise_edition.debug_session.events"
local updates   = require "kong.enterprise_edition.debug_session.updates"
local instrum   = require "kong.enterprise_edition.debug_session.instrumentation"
local redis_instrum = require "kong.enterprise_edition.debug_session.instrumentation.redis"
local socket_instrum = require "kong.enterprise_edition.debug_session.instrumentation.socket"
local SPAN_ATTRIBUTES = require "kong.enterprise_edition.debug_session.instrumentation.attributes".SPAN_ATTRIBUTES
local utils = require "kong.enterprise_edition.debug_session.utils"

local get_ctx_key = utils.get_ctx_key
local log = utils.log
local fmt = string.format

local kong = kong
local ngx_DEBUG = ngx.DEBUG
local ngx_INFO = ngx.INFO
local ngx_WARN = ngx.WARN
local ngx_ERR = ngx.ERR

local RPC_ACTION_START = "START"
local RPC_ACTION_STOP = "STOP"
local SKIP_SAMPLE_CTX_KEY = get_ctx_key("skip_sample")


local instance = nil

local _M = {}
_M.__index = _M
_M.module_enabled = false

local function is_module_enabled()
  return _M.module_enabled ~= false
end

local function stop_sampling_for_request()
  ngx.ctx[SKIP_SAMPLE_CTX_KEY] = true
end

function _M:should_record_samples()
  return self:is_active() and not ngx.ctx[SKIP_SAMPLE_CTX_KEY]
end

local NOOP_FUN = function() end
local NOOP_DEBUG_SESSION = {
  new = NOOP_FUN,
  start_updates_timer = NOOP_FUN,
  init_worker = NOOP_FUN,
  is_active = function() return false end,
  should_record_samples = function() return false end,
  sample = NOOP_FUN,
  enrich_root_span = NOOP_FUN,
  report = NOOP_FUN,
  init_session = NOOP_FUN,
  end_session = NOOP_FUN,
  clear_session_data = NOOP_FUN,
  set_start_session = NOOP_FUN,
  set_stop_session = NOOP_FUN,
  broadcast_end_session = NOOP_FUN,
  handle_action = NOOP_FUN,
  process_updates = NOOP_FUN,
  update_sessions_from_cp = NOOP_FUN,
  module_enabled = false,
}

function _M:new(enabled)
  enabled = enabled or false
  if ngx.config.subsystem ~= "http" or not enabled then
    return NOOP_DEBUG_SESSION
  end

  -- singleton
  if instance then
    return instance
  end

  instance = {
    context = context:new(),
    sampler = sampler:new(),
    reporter = reporter:new(),
  }
  setmetatable(instance, self)
  return instance
end

-- timer to check/report session updates
-- this only runs on one worker to limit rpc calls
-- the result is propagated to all workers via worker events
function _M:start_updates_timer()
  if not is_module_enabled() then
    return
  end

  ngx.timer.every(5, function()
    -- handle DP-initiated stops:

    -- sample limit exceeded
    if self.context:get_exceeded_max_samples() then
      log(ngx_INFO, "sample limit exceeded: ending session")
      local session_id = self.context:get_session_id()
      updates.report_state(session_id, "done")
      self:broadcast_end_session(session_id)

    -- expired
    elseif self.context:is_session_expired() then
      local session_id = self.context:get_session_id()
      log(ngx_INFO, "session ", session_id, " expired")
      updates.report_state(session_id, "done")
      self:broadcast_end_session(session_id)
    end

    self:update_sessions_from_cp()
  end)
end

function _M:init_worker()
  if not kong.configuration.konnect_mode then
    return
  end
  _M.module_enabled = true


  -- initialize worker events
  events.init(
    function()
      return self.sampler:init_worker()
    end
  )

  if ngx.worker.id() == 0 then
    self:start_updates_timer()
  end
end

function _M:is_active()
  return is_module_enabled() and self.context:is_session_active()
end

function _M:sample()
  if not self:is_active() then
    return
  end

  local sampled_in = self.sampler:sample_in()
  if not sampled_in then
    stop_sampling_for_request()
  end
end

function _M:enrich_root_span()
  if not is_module_enabled() then
    return
  end
  local root_span = instrum.get_root_span()
  if not root_span then
    return
  end
  -- Kong internal attributes
  local route = kong.router.get_route()
  local route_id = route and route.id
  root_span:set_attribute(SPAN_ATTRIBUTES.KONG_ROUTE_ID, route_id)
  local service = kong.router.get_service()
  local service_id = service and service.id
  root_span:set_attribute(SPAN_ATTRIBUTES.KONG_SERVICE_ID, service_id)
  local consumer =  kong.client.get_consumer()
  local consumer_id = consumer and consumer.id
  root_span:set_attribute(SPAN_ATTRIBUTES.KONG_CONSUMER_ID, consumer_id)

  -- ngx attributes
  root_span:set_attribute(SPAN_ATTRIBUTES.TLS_SERVER_NAME_INDICATION, ngx.var.upstream_ssl_server_name)
  -- seconds to ms -> * 1e3
  local latency_total_ms = ngx.var.request_time * 1e3
  root_span:set_attribute(SPAN_ATTRIBUTES.KONG_LATENCY_TOTAL_MS, latency_total_ms)
  -- Record total time spent doing Redis IO, Socket IO
  root_span:set_attribute(SPAN_ATTRIBUTES.KONG_TOTAL_IO_REDIS_MS, redis_instrum.get_total_time())
  root_span:set_attribute(SPAN_ATTRIBUTES.KONG_TOTAL_IO_TCPSOCKET_MS, socket_instrum.get_total_time())
end

-- report everything that was collected
function _M:report()
  -- silently exit when the module is not enabled or there is no active session
  if not is_module_enabled() or not self:is_active() then
    return
  end

  if not self:should_record_samples() then
    log(ngx_DEBUG, "request sampled out: skip reporting")
    return
  end

  if instrum.is_session_activating() then
    log(ngx_DEBUG, "debug session is activating: skip reporting")
    return
  end

  if not self.reporter:has_traces() then
    log(ngx_DEBUG, "debug session collected no traces: skip reporting")
    return
  end

  local count = self.context:incr_counter()
  if self.context:check_exceeded_max_samples(count) then
    log(ngx_DEBUG, "sample limit exceeded: skip reporting")
    return
  end

  if self.context:is_session_expired() then
    log(ngx_DEBUG, "debug session expired: skip reporting")
    return
  end

  local session_id = self.context:get_session_id()
  self.reporter:report_traces(session_id)
end

function _M:init_session(session_id)
  log(ngx_DEBUG, string.format("debug session %s started", session_id))

  self.reporter:init()
end

function _M:end_session(session_id)
  log(ngx_DEBUG, string.format("debug session %s stopped", session_id))

  local _, err = self.reporter:stop()
  if err then
    log(ngx_WARN, "failed stopping debug reporter: ", err)
  end
end

-- private functions

function _M:clear_session_data()
  self.context:flush()
end

function _M:set_start_session(cp_session)
  -- only start a session if the session from cp_session is not equal to
  -- the current session and if there is no active session (TBD)
  if not cp_session then
    return nil, "no session data"
  end
  if cp_session.id == self.context:get_session_id() then
    return nil, "session already started"
  end
  -- set the session data: this only needs to happen once
  -- because data lives in the shm
  local ok, err = self.context:set_session(cp_session)
  if not ok then
    return nil, fmt("failed setting session context: %s", err)
  end
  -- broadcast "start" to workers
  events.start(cp_session.id)
  return true
end

function _M:broadcast_end_session(session_id)
  -- clear session data: this only needs to happen once
  -- because data lives in the shm
  self:clear_session_data()
  -- broadcast "stop" to workers
  events.stop(session_id)
end

function _M:set_stop_session(cp_session)
  -- verify the STOP action refers to the current session and if so, stop it
  -- only stop sessions with matching session_id (current vs cp_session)
  if not cp_session then
    return nil, "no session data"
  end

  local current_session_id = self.context:get_session_id()
  if cp_session.id ~= current_session_id then
    return nil, fmt("stop session failed: ids %s and %s mismatch",
                    cp_session.id, current_session_id)
  end

  -- end session for all workers:
  self:broadcast_end_session(cp_session.id)
  return true
end

function _M:handle_action(cp_session)
  local action = cp_session and cp_session.action
  if action == RPC_ACTION_START then
    log(ngx_DEBUG, "starting debug session")
    local ok, err = self:set_start_session(cp_session)
    if not ok then
      log(ngx_WARN, "failed starting debug session: ", err)
    end
  end
  if action == RPC_ACTION_STOP then
    log(ngx_DEBUG, "stopping debug session")
    local ok, err = self:set_stop_session(cp_session)
    if not ok then
      log(ngx_WARN, "failed stopping debug session: ", err)
    end
  end
end

function _M:process_updates(data)
  if not is_module_enabled() then
    return
  end
  if not data then
    return nil, "no data"
  end

  local cp_sessions = data.sessions
  if not cp_sessions or #cp_sessions == 0 then
    return
  end

  if type(cp_sessions) ~= "table" then
    log(ngx_ERR, "failed to get pending session: ", tostring(cp_sessions))
    return
  end
  for _, cp_session in ipairs(cp_sessions) do
    if cp_session == nil or type(cp_session) ~= "table" then
      log(ngx_ERR, "failed to get pending session: ", tostring(cp_session))
      return
    end

    -- handle the action for the session either, start or stop
    self:handle_action(cp_session)
  end
end

function _M:update_sessions_from_cp()
  if not is_module_enabled() then
    return
  end

  -- gettig session updates from CP via RPC
  local last_event_id = self.context:get_event_id()
  local res, err = updates.get(last_event_id)
  if not res then
    log(ngx_DEBUG, "failed to get debug session updates: ", err)
    return
  end
  -- store the event id for the next request
  self.context:set_event_id(res.event_id)
  -- processing updates
  self:process_updates(res)
end


return _M
