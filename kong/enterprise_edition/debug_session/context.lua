-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local shm = require "kong.enterprise_edition.debug_session.shm"
local utils = require "kong.enterprise_edition.debug_session.utils"

local log = utils.log
local ngx_ERR = ngx.ERR

local _M = {}
_M.__index = _M

function _M:new()
  local obj = {
    shm = shm:new(),
  }
  setmetatable(obj, _M)
  return obj
end

function _M:get_event_id()
  return ngx.shared.kong:get("active_tracing.event_id")
end

function _M:set_event_id(event_id)
  return ngx.shared.kong:set("active_tracing.event_id", event_id)
end

function _M:get_session_id()
  return self.shm:get("id")
end

function _M:is_session_active()
  return self:get_session_id() ~= nil and self.shm:get("active") == true
end

function _M:set_session_active()
  self.shm:set("active", true)
  self.shm:set("started_at", ngx.now())
end

function _M:set_session_inactive()
  self.shm:set("active", false)
end

function _M:get_session_remaining_ttl()
  local duration = self.shm:get("duration")
  local started_at = self.shm:get("started_at")
  if not duration or not started_at then
    return nil, "missing session lifetime data"
  end

  return duration - (ngx.now() - started_at)
end

function _M:is_session_expired()
  local remaining_ttl, err = self:get_session_remaining_ttl()
  if not remaining_ttl then
    return nil, err
  end
  if remaining_ttl <= 0 then
    return true
  end
  return false
end

function _M:get_session_max_samples()
  return self.shm:get("max_samples")
end

function _M:get_exceeded_max_samples()
  return self.shm:get("exceeded_max_samples") == true
end

function _M:set_exceeded_max_samples()
  self.shm:set("exceeded_max_samples", true)
end

function _M:check_exceeded_max_samples(count)
  local sample_limit = self:get_session_max_samples()
  if not sample_limit then
    log(ngx_ERR, "missing sample limit: terminating session")
    self:set_exceeded_max_samples()
    self:set_session_inactive()
    return true
  end

  if count and count > sample_limit then
    self:set_exceeded_max_samples()
    self:set_session_inactive()
    return true
  end
  return false
end

function _M:set_session(session)
  if not session then
    return nil, "missing session"
  end
  if (not session.id) or (not session.action) then
    return nil, "invalid session"
  end

  for k, v in pairs(session) do
    self.shm:set(k, v)
  end
  self:set_session_active()
  return true
end

function _M:incr_counter()
  return self.shm:incr()
end

function _M:get_sampling_rule()
  return self.shm:get("sampling_rule") or ""
end

function _M:flush()
  self.shm:flush()
end


return _M
