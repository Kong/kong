-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local pb = require("pb")

local KEEPALIVE_INTERVAL = 1
local DELAY_LOWER_BOUND  = 0
local DELAY_UPPER_BOUND  = 3

local ngx_log = ngx.log
local ngx_INFO = ngx.INFO
local ngx_ERR = ngx.ERR

local _M = {}
local _MT = { __index = _M }


local function random(low, high)
  return low + math.random() * (high - low);
end


local function keepalive_handler(premature, self)
  if premature then
    return
  end

  if not self.ws_send_func then
    ngx_log(ngx_INFO, self._log_prefix, "no analytics websocket connection, skipping this round of keepalive")
    return
  end

  -- Random delay to avoid thundering herd.
  -- We should not do this at the beginning of this function
  -- because this will block the coroutine the timer is running in
  -- even if we don't need to send the keepalive message (no connection).
  -- So we should do this after we check if the connection is available.
  ngx.sleep(KEEPALIVE_INTERVAL + random(DELAY_LOWER_BOUND, DELAY_UPPER_BOUND))

  -- DO NOT YIELD IN THIS SECTION [[
  -- the connection might be closed after the ngx.sleep (yielding)
  if not self.ws_send_func then
    ngx_log(ngx_INFO, self._log_prefix, "no analytics websocket connection, skipping this round of keepalive")
    return
  end

  self.ws_send_func(self:get_empty_payload())
  -- DO NOT YIELD IN THIS SECTION ]]
end


function _M:get_empty_payload()
  return pb.encode(self.pb_def_empty, {})
end


function _M:is_connected()
  return self.ws_send_func ~= nil
end


function _M:is_running()
  return self.running
end


function _M:is_initialized()
  return self.initialized
end


function _M:init_connection()
  local uri = self.uri
  local server_name = self.server_name
  local clustering = kong.clustering or require("kong.clustering").new(kong.configuration)

  assert(ngx.timer.at(0, clustering.telemetry_communicate, clustering, uri, server_name, function(connected, send_func)
    if connected then
      ngx_log(ngx_INFO, self._log_prefix, "worker id: ", (ngx.worker.id() or -1),
          ". " .. self.name .. " websocket is connected: ", uri)
      self.ws_send_func = send_func

    else
      ngx_log(ngx_INFO, self._log_prefix, "worker id: ", (ngx.worker.id() or -1),
          ". " .. self.name .. " websocket is disconnected: ", uri)
      self.ws_send_func = nil
    end
  end), nil)

  self.initialized = true
  self:start()
end


function _M:start()
  local hdl, err = kong.timer:named_every(
    self.name .. "_reporter_keepalive",
    KEEPALIVE_INTERVAL,
    keepalive_handler,
    self
  )
  if not hdl then
    local msg = string.format(
      "failed to start the initial " .. self.name .. "_reporter timer for worker %d: %s",
      ngx.worker.id(), err or ""
    )
    ngx_log(ngx_ERR, self._log_prefix, msg)
  end

  ngx_log(ngx_INFO, self._log_prefix, "initial  " .. self.name .. "_reporter keepalive timer started for worker ", ngx.worker.id())

  self.keepalive_timer = hdl
  self.running = true
end


function _M:stop()
  ngx_log(ngx_INFO, self._log_prefix, "stopping " .. self.name .. " reporting")
  self.running = false

  if not self.keepalive_timer then
    ngx_log(ngx_INFO, self._log_prefix, "no " .. self.name .. " keepalive timer to stop for worker ", ngx.worker.id())
    return
  end

  local ok, err = kong.timer:cancel(self.keepalive_timer)
  if not ok then
    local msg = string.format(
      "failed to stop the " .. self.name .. " keepalive timer for worker %d: %s",
      ngx.worker.id(), err
    )
    ngx_log(ngx_ERR, self._log_prefix, msg)
  end

  self.keepalive_timer = nil
  ngx_log(ngx_INFO, self._log_prefix, self.name .. " keepalive timer stopped for worker ", ngx.worker.id())
end


function _M:send(payload)
  -- DO NOT YIELD IN THIS SECTION [[
  -- the connection might be closed after the yielding

  if not self.ws_send_func then
    -- let the queue know that we are not able to send the entries
    -- so it can retry later or drop them after serveral retries
    return false, "no websocket connection from worker " .. ngx.worker.id()
  end

  self.ws_send_func(payload)
  -- DO NOT YIELD IN THIS SECTION ]]

  return true
end


_M.new = function(config)
  local self = {
    name = config.name,
    _log_prefix = "[" .. config.name .. "] ",
    cluster_endpoint = config.cluster_endpoint,
    path = config.path,
    uri = config.uri,
    server_name = config.server_name,
    pb_def_empty = config.pb_def_empty,
    ws_send = nil,
    initialized = false,
    running = false,
  }
  return setmetatable(self, _MT)
end


return _M
