-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local subsystem = ngx.config.subsystem

local msgpack = require "MessagePack"
local mp_pack = msgpack.pack
local mp_unpack = msgpack.unpack
local cjson_encode = require "cjson".encode
local kong = kong
local knode  = (kong and kong.node) and kong.node or
               require "kong.pdk.node".new()
local queue = require "kong.tools.queue"

local new_tab = require("table.new")
local clear_tab = require("table.clear")
local KONG_VERSION = kong.version
local KONG_NODE_ID = knode.get_id()
local KONG_HOSTNAME = knode.get_hostname()

local BUFFER_SIZE = 64

local _M = {}
local mt = { __index = _M }

_M.TYPE = {
  PRODUCER = 1,
  CONSUMER = 2,
}

local dummy_response_msg = "PONG"

local _log_prefix = "[messaging-utils] "


local function get_log_prefix(self)
  return _log_prefix .. "[" .. self.message_type .. "] "
end

local function get_dummy_heartbeat_msg(self)
  return cjson_encode({
    type = self.message_type,
    -- TODO: msgid for re-transmit
    -- cjson decodes nil to lightuserdata null, this is unhandled
    -- in db strategies, to avoid introducing too much change we
    -- use mp_pack to wrap inner payloads
    data = mp_pack({
      self.message_type_version,
      self.message_type,
      {},
    }),
  })
end

local function flush_cp(premature, self)
  if premature then
    return
  end

  local sent = false

  if self.ws_send_func then
    while true do
      local v, err = self.SHM:rpop(self.SHM_KEY)
      if err then
        ngx.log(ngx.WARN, get_log_prefix(self), "cannot get rpop shm buffer: ", err)
        break
      elseif v == nil then
        break
      end

      local _, err = self.ws_send_func(v)
      if err then
        local _, err = self.SHM:lpush(self.SHM_KEY, v)
        ngx.log(ngx.WARN, get_log_prefix(self), "cannot putting back to shm buffer: ", err)
        break
      end
      sent = true

      ngx.log(ngx.DEBUG, get_log_prefix(self), "flush ", #v, " bytes to CP")
    end

    -- this is like a ping in case no other data is produced
    if not sent then
      self.ws_send_func(get_dummy_heartbeat_msg(self))
    end
  else
    ngx.log(ngx.DEBUG, get_log_prefix(self), "websocket is not ready yet, waiting for next try")
  end


  local len, err = self.SHM:llen(self.SHM_KEY)
  if err then
    ngx.log(ngx.WARN, _log_prefix, "cannot get length of shm buffer: ", err)
  elseif len > self.buffer_retry_size then
    ngx.log(ngx.WARN, _log_prefix, "cleaned up ", len - self.buffer_retry_size, " unflushed buffer")
    for _=0, len - self.buffer_retry_size do
      self.SHM:rpop(self.SHM_KEY)
    end
  end

  assert(ngx.timer.at(self.buffer_ttl, flush_cp, self))
end

local function start_ws_client(self, server_name)
  local uri = "wss://" .. self.cluster_endpoint .. "/v1/ingest?node_id=" ..
    KONG_NODE_ID .. "&node_hostname=" .. KONG_HOSTNAME ..
    "&node_version=" .. KONG_VERSION

  local log_prefix = get_log_prefix(self)
  assert(ngx.timer.at(0, kong.clustering.telemetry_communicate, kong.clustering, uri, server_name, function(connected, send_func)
    if connected then
      ngx.log(ngx.DEBUG, log_prefix, "telemetry websocket is connected")
      self.ws_send_func = send_func
    else
      ngx.log(ngx.DEBUG, log_prefix, "telemetry websocket is disconnected")
      self.ws_send_func = nil
    end
  end), nil)
end

local function check_address(address)
  local host, port
  local m, _ = ngx.re.match(address, [[([^:]+):(\d+)]], "jo")
  if m then
    host = m[1]
    port = tonumber(m[2])
  end

  if not host or not port then
    error("Malformed cluster endpoint address", 2)
  end
end

local function check_opts(opts)
  if not opts.message_type then
    return false, "'message_type' is missing"
  end

  if not opts.serve_ingest_func then
    return false, "'serve_ingest_func' is missing"
  end

  if not opts.shm then
    return false, "'SHM' is missing"
  end

  if not opts.shm_key then
    return false, "'SHM_KEY' is missing"
  end

  if not opts.type or (opts.type ~= _M.TYPE.PRODUCER
    and opts.type ~= _M.TYPE.CONSUMER) then
    return false, "'TYPE' is missing or is not supported"
  end

  return true
end

--
-- @param opts - configuration options
function _M.new(opts)
  local ok, err = check_opts(opts)
  if not ok then
    return nil, err
  end

  if opts.type == _M.TYPE.PRODUCER then
    -- validate cluster endpoint address
    check_address(opts.cluster_endpoint)
  end

  local self = {
    -- Is it consumer or producer
    type = opts.type,
    cluster_endpoint = opts.cluster_endpoint,
    message_type = opts.message_type,
    message_type_version = opts.message_type_version or "v1",
    serve_ingest = opts.serve_ingest_func,
    SHM = opts.shm,
    SHM_KEY = opts.shm_key,
    buffer = opts.buffer or new_tab(BUFFER_SIZE, 0),
    buffer_idx = 1,
    buffer_age = 0,
    buffer_ttl = opts.buffer_ttl or 2,
    buffer_retry_size = opts.buffer_retry_size or 60,
  }

  return setmetatable(self, mt)
end

local function ingest(handler_conf, items)
  local serve_ingest = handler_conf.serve_ingest
  local node_id = handler_conf.node_id
  local hostname = handler_conf.hostname

  for _, item in ipairs(items) do
    if item ~= nil then
      local ok, err = pcall(serve_ingest, item, node_id, hostname)
      if not ok then
        ngx.log(ngx.ERR, _log_prefix, "ingestion handler threw an exception: ", err)
        return false, err
      end

      return true
    end
  end
end

function _M:register_for_messages()
  if not kong.clustering then
    ngx.log(ngx.WARN, _log_prefix, "Unable to register for messages, clustering object is not available")
    return
  end

  kong.clustering.register_server_on_message(self.message_type, function(msg, queued_send, node_id, hostname)
    -- decode message
    local payload, err = self.unpack_message(msg, self.message_type, self.message_type_version)
    if err then
      ngx.log(ngx.ERR, _log_prefix, err)
      return ngx.exit(400)
    end

    -- just send a empty response for now
    -- this can be implemented into a per msgid retry in the future
    queued_send(dummy_response_msg)

    if #payload == 0 then
      return
    end
    ngx.log(ngx.DEBUG, "recv size ", #msg.data, " sets ", #payload/2)

    local ok, err = queue.enqueue(
      -- queue_conf
      {
        name = "messaging_" .. tostring(self.message_type),
        max_batch_size = 1,
        max_coalescing_delay = 0,
        max_entries = 1000,
        -- even if payloads bufferd in the queue are string type,
        -- we can't predict the length of each of them, so it would
        -- be better not to set the max_bytes value.
        -- max_bytes = nil,
        initial_retry_delay = 1,
        -- the max time for a batch to retry
        max_retry_time = 120,
        -- delay between retries
        max_retry_delay = 60,
        concurrency_limit = 1,
      },
      -- handler
      ingest,
      -- handler_conf
      {
        serve_ingest = self.serve_ingest,
        node_id = node_id,
        hostname = hostname
      },
      -- item
      payload
    )
    if not ok then
      ngx.log(ngx.WARN, get_log_prefix(self), err)
    end
  end)

  ngx.log(ngx.DEBUG, get_log_prefix(self), "registered on_message function")
end

function _M:start_client(server_name)
  if ngx.worker.id() == 0 and subsystem == "http" then
    start_ws_client(self, server_name)

    assert(ngx.timer.at(self.buffer_ttl, flush_cp, self))
  end
  return true
end

function _M:send_message(typ, data, flush_now)
  if self.buffer_idx == 1 then
    self.buffer_age = ngx.now()
  end

  self.buffer[self.buffer_idx] = typ
  self.buffer[self.buffer_idx+1] = data
  self.buffer_idx = self.buffer_idx + 2

  if not flush_now then
    ngx.update_time()
    -- TODO: this relies on the behaviour of timer of vitals and node_stats is flushed
    -- every 10 seconds.
    if self.buffer_idx < BUFFER_SIZE and ngx.now() - self.buffer_age < self.buffer_ttl then
      return true
    end
  end

  local data = cjson_encode({
    type = self.message_type,
    -- TODO: msgid for re-transmit
    -- cjson decodes nil to lightuserdata null, this is unhandled
    -- in db strategies, to avoid introducing too much change we
    -- use mp_pack to wrap inner payloads
    data = mp_pack({
      self.message_type_version,
      self.message_type,
      self.buffer,
    }),
  })
  self.buffer_idx = 1
  clear_tab(self.buffer)

  local _, err = self.SHM:lpush(self.SHM_KEY, data)
  if err then
    return false, err
  end

  return true
end

function _M.unpack_message(msg, type, version)
  local v, t, payload = unpack(mp_unpack(msg.data))
  if v ~= version or t ~= type then
    return nil, "ingest version or type doesn't match, expect version "
      .. type .." type "
      .. version .. ", got version " .. v .." type " .. t
  end
  return payload, nil
end

return _M
