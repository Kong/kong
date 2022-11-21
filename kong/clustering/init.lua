-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}
local _MT = { __index = _M, }

local clustering_utils = require("kong.clustering.utils")
local constants = require("kong.constants")

local pl_file = require("pl.file")
local pl_tablex = require("pl.tablex")
local ws_server = require("resty.websocket.server")
local ws_client = require("resty.websocket.client")
local ssl = require("ngx.ssl")
local openssl_x509 = require("resty.openssl.x509")
local sub = string.sub
local assert = assert
local pairs = pairs
local sort = table.sort
local type = type


local is_dp_worker_process = clustering_utils.is_dp_worker_process

local check_for_revocation_status = clustering_utils.check_for_revocation_status

-- XXX EE
local semaphore = require("ngx.semaphore")
local cjson = require("cjson.safe")
local utils = require("kong.tools.utils")
local declarative = require("kong.db.declarative")
local setmetatable = setmetatable
local ngx = ngx
local ngx_log = ngx.log
local ngx_WARN = ngx.WARN
local ngx_NOTICE = ngx.NOTICE
local ngx_var = ngx.var
local cjson_decode = cjson.decode
local kong = kong
local ngx_exit = ngx.exit
local exiting = ngx.worker.exiting
local table_insert = table.insert
local table_remove = table.remove
local inflate_gzip = utils.inflate_gzip
local deflate_gzip = utils.deflate_gzip
local get_cn_parent_domain = utils.get_cn_parent_domain
local ngx_ERR = ngx.ERR
local ngx_DEBUG = ngx.DEBUG


local server_on_message_callbacks = {}
local MAX_PAYLOAD = kong.configuration.cluster_max_payload
local WS_OPTS = {
  timeout = constants.CLUSTERING_TIMEOUT,
  max_payload_len = MAX_PAYLOAD,
}

local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH
local _log_prefix = "[clustering] "


-- Sends "clustering", "push_config" to all workers in the same node, including self
local function post_push_config_event()
  local res, err = kong.worker_events.post("clustering", "push_config")
  if not res then
    ngx_log(ngx_ERR, _log_prefix, "unable to broadcast event: ", err)
  end
end


-- Handles "clustering:push_config" cluster event
local function handle_clustering_push_config_event(data)
  ngx_log(ngx_DEBUG, _log_prefix, "received clustering:push_config event for ", data)
  post_push_config_event()
end


-- Handles "dao:crud" worker event and broadcasts "clustering:push_config" cluster event
local function handle_dao_crud_event(data)
  if type(data) ~= "table" or data.schema == nil or data.schema.db_export == false then
    return
  end

  kong.cluster_events:broadcast("clustering:push_config", data.schema.name .. ":" .. data.operation)

  -- we have to re-broadcast event using `post` because the dao
  -- events were sent using `post_local` which means not all workers
  -- can receive it
  post_push_config_event()
end


function _M.new(conf)
  assert(conf, "conf can not be nil", 2)

  local self = {
    conf = conf,
  }

  setmetatable(self, _MT)

  local cert = assert(pl_file.read(conf.cluster_cert))
  self.cert = assert(ssl.parse_pem_cert(cert))

  cert = openssl_x509.new(cert, "PEM")
  self.cert_digest = cert:digest("sha256")
  local _, cert_cn_parent = get_cn_parent_domain(cert)

  if conf.cluster_allowed_common_names and #conf.cluster_allowed_common_names > 0 then
    self.cn_matcher = {}
    for _, cn in ipairs(conf.cluster_allowed_common_names) do
      self.cn_matcher[cn] = true
    end

  else
    self.cn_matcher = setmetatable({}, {
      __index = function(_, k)
        return string.match(k, "^[%a%d-]+%.(.+)$") == cert_cn_parent
      end
    })

  end

  local key = assert(pl_file.read(conf.cluster_cert_key))
  self.cert_key = assert(ssl.parse_pem_priv_key(key))

  if conf.role == "control_plane" then
    self.wrpc_handler =
      require("kong.clustering.wrpc_control_plane").new(self.conf, self.cert_digest)
  end


  return self
end


function _M:validate_client_cert(cert, log_prefix, log_suffix)
  if not cert then
    return false, "data plane failed to present client certificate during handshake"
  end

  local err
  cert, err = openssl_x509.new(cert, "PEM")
  if not cert then
    return false, "unable to load data plane client certificate during handshake: " .. err
  end
  setmetatable(self, _MT)

  if kong.configuration.cluster_mtls == "shared" then
    local digest, err = cert:digest("sha256")
    if not digest then
      return false, "unable to retrieve data plane client certificate digest during handshake: " .. err
    end

    if digest ~= self.cert_digest then
      return false, "data plane presented incorrect client certificate during handshake (expected: " ..
                    self.cert_digest .. ", got: " .. digest .. ")"
    end

  elseif kong.configuration.cluster_mtls == "pki_check_cn" then
    local cn, _ = get_cn_parent_domain(cert)
    if not cn then
      return false, "data plane presented incorrect client certificate " ..
                    "during handshake, unable to extract CN: " .. cn

    elseif not self.cn_matcher[cn] then
      return false, "data plane presented client certificate with incorrect CN " ..
                    "during handshake, got: " .. cn
    end

  elseif kong.configuration.cluster_ocsp ~= "off" then
    local ok
    ok, err = check_for_revocation_status()
    if ok == false then
      err = "data plane client certificate was revoked: " ..  err
      return false, err

    elseif not ok then
      if self.conf.cluster_ocsp == "on" then
        err = "data plane client certificate revocation check failed: " .. err
        return false, err

      else
        if log_prefix and log_suffix then
          ngx_log(ngx_WARN, log_prefix, "data plane client certificate revocation check failed: ", err, log_suffix)
        else
          ngx_log(ngx_WARN, "data plane client certificate revocation check failed: ", err)
        end
      end
    end
  end

  return true
end


-- XXX EE telemetry_communicate is written for hybrid mode over websocket.
-- It should be migrated to wRPC later.
-- ws_event_loop, is_timeout, and send_ping is for handle_cp_telemetry_websocket only.
-- is_timeout and send_ping is copied here to keep the code functioning.

local function is_timeout(err)
  return err and sub(err, -7) == "timeout"
end

local function send_ping(c, log_suffix)
  log_suffix = log_suffix or ""

  local hash = declarative.get_current_hash()

  if hash == true then
    hash = DECLARATIVE_EMPTY_CONFIG_HASH
  end

  local _, err = c:send_ping(hash)
  if err then
    ngx_log(is_timeout(err) and ngx_NOTICE or ngx_WARN, _log_prefix,
            "unable to send ping frame to control plane: ", err, log_suffix)

  else
    ngx_log(ngx_DEBUG, _log_prefix, "sent ping frame to control plane", log_suffix)
  end
end

-- XXX EE only used for telemetry, remove cruft
local function ws_event_loop(ws, on_connection, on_error, on_message)
  local sem = semaphore.new()
  local queue = { sem = sem, }

  local function queued_send(msg)
    table_insert(queue, msg)
    queue.sem:post()
  end

  local recv = ngx.thread.spawn(function()
    while not exiting() do
      local data, typ, err = ws:recv_frame()
      if err then
        ngx.log(ngx.ERR, "error while receiving frame from peer: ", err)
        if ws.close then
          ws:close()
        end

        if on_connection then
          local _, err = on_connection(false)
          if err then
            ngx_log(ngx_ERR, "error when executing on_connection function: ", err)
          end
        end

        if on_error then
          local _, err = on_error(err)
          if err then
            ngx_log(ngx_ERR, "error when executing on_error function: ", err)
          end
        end
        return
      end

      if (typ == "ping" or typ == "binary") and on_message then
        local cbs
        if typ == "binary" then
          data = assert(inflate_gzip(data))
          data = assert(cjson_decode(data))

          cbs = on_message[data.type]
        else
          cbs = on_message[typ]
        end

        if cbs then
          for _, cb in ipairs(cbs) do
            local _, err = cb(data, queued_send)
            if err then
              ngx_log(ngx_ERR, "error when executing on_message function: ", err)
            end
          end
        end
      elseif typ == "pong" then
        ngx_log(ngx_DEBUG, "received PONG frame from peer")
      end
    end
    end)

    local send = ngx.thread.spawn(function()
      while not exiting() do
        local ok, err = sem:wait(10)
        if ok then
          local payload = table_remove(queue, 1)
          assert(payload, "client message queue can not be empty after semaphore returns")

          if payload == "PONG" then
            local _
            _, err = ws:send_pong()
            if err then
              ngx_log(ngx_ERR, "failed to send PONG back to peer: ", err)
              return ngx_exit(ngx_ERR)
            end

            ngx_log(ngx_DEBUG, "sent PONG packet back to peer")
          elseif payload == "PING" then
            local _
            _, err = send_ping(ws)
            if err then
              ngx_log(ngx_ERR, "failed to send PING to peer: ", err)
              return ngx_exit(ngx_ERR)
            end

            ngx_log(ngx_DEBUG, "sent PING packet to peer")
          else
            payload = assert(deflate_gzip(payload))
            local _, err = ws:send_binary(payload)
            if err then
              ngx_log(ngx_ERR, "unable to send binary to peer: ", err)
            end
          end

        else -- not ok
          if err ~= "timeout" then
            ngx_log(ngx_ERR, "semaphore wait error: ", err)
          end
        end
      end
    end)

    local wait = function()
      local ok, err, perr = ngx.thread.wait(recv, send)
      ngx.thread.kill(recv)
      ngx.thread.kill(send)

      return ok, err, perr
    end

    return queued_send, wait

end

local function telemetry_communicate(premature, self, uri, server_name, on_connection, on_message)
  if premature then
    -- worker wants to exit
    return
  end

  local reconnect = function(delay)
    return ngx.timer.at(delay, telemetry_communicate, self, uri, server_name, on_connection, on_message)
  end

  local c = assert(ws_client:new(WS_OPTS))

  local opts = {
    ssl_verify = true,
    client_cert = self.cert,
    client_priv_key = self.cert_key,
    server_name = server_name,
  }

  local res, err = c:connect(uri, opts)
  if not res then
    local delay = math.random(5, 10)

    ngx_log(ngx_ERR, "connection to control plane ", uri, " broken: ", err,
            " retrying after ", delay , " seconds")

    assert(reconnect(delay))
    return
  end

  local queued_send, wait = ws_event_loop(c,
    on_connection,
    function()
      assert(reconnect(9 + math.random()))
    end,
    on_message)


  if on_connection then
    local _, err = on_connection(true, queued_send)
    if err then
      ngx_log(ngx_ERR, "error when executing on_connection function: ", err)
    end
  end

  wait()

end

_M.telemetry_communicate = telemetry_communicate

function _M:handle_cp_telemetry_websocket()
  -- use mutual TLS authentication
  local ok, err = self:validate_client_cert(ngx_var.ssl_client_raw_cert)
  if not ok then
    ngx_log(ngx_ERR, err)
    return ngx_exit(444)
  end

  local node_id = ngx_var.arg_node_id
  if not node_id then
    ngx_exit(400)
  end

  local wb, err = ws_server:new(WS_OPTS)
  if not wb then
    ngx_log(ngx_ERR, "failed to perform server side WebSocket handshake: ", err)
    return ngx_exit(444)
  end

  local current_on_message_callbacks = {}
  for k, v in pairs(server_on_message_callbacks) do
    current_on_message_callbacks[k] = v
  end

  local _, wait = ws_event_loop(wb,
    nil,
    function(_)
      return ngx_exit(ngx_ERR)
    end,
    current_on_message_callbacks)

  wait()

function _M:handle_wrpc_websocket()
  return self.wrpc_handler:handle_cp_websocket()
end


function _M:init_cp_worker(plugins_list)
  -- The "clustering:push_config" cluster event gets inserted in the cluster when there's
  -- a crud change (like an insertion or deletion). Only one worker per kong node receives
  -- this callback. This makes such node post push_config events to all the cp workers on
  -- its node
  kong.cluster_events:subscribe("clustering:push_config", handle_clustering_push_config_event)

  -- The "dao:crud" event is triggered using post_local, which eventually generates an
  -- ""clustering:push_config" cluster event. It is assumed that the workers in the
  -- same node where the dao:crud event originated will "know" about the update mostly via
  -- changes in the cache shared dict. Since data planes don't use the cache, nodes in the same
  -- kong node where the event originated will need to be notified so they push config to
  -- their data planes
  kong.worker_events.register(handle_dao_crud_event, "dao:crud")

  self.wrpc_handler:init_worker(plugins_list)
end

function _M:init_dp_worker(plugins_list)
  local start_dp = function(premature)
    if premature then
      return
    end

    self.child = require("kong.clustering.wrpc_data_plane").new(self.conf, self.cert, self.cert_key)

    --- XXX EE: clear private key as it is not needed after this point
    self.cert_private = nil
    --- EE

    self.child:init_worker(plugins_list)
  end

  assert(ngx.timer.at(0, start_dp))
end

function _M:init_worker()
  local plugins_list = assert(kong.db.plugins:get_handlers())
  sort(plugins_list, function(a, b)
    return a.name:lower() < b.name:lower()
  end)

  plugins_list = pl_tablex.map(function(p)
    return { name = p.name, version = p.handler.VERSION, }
  end, plugins_list)

  local role = self.conf.role
  if role == "control_plane" then
    self:init_cp_worker(plugins_list)
    return
  end

  if role == "data_plane" and is_dp_worker_process() then
    self:init_dp_worker(plugins_list)
  end
end

function _M.register_server_on_message(typ, cb)
  if not server_on_message_callbacks[typ] then
    server_on_message_callbacks[typ] = { cb }
  else
    table.insert(server_on_message_callbacks[typ], cb)
  end
end

function _M:exit_worker()
  if self.conf.role == "control_plane" then
    self.wrpc_handler:exit_worker()
  end
end

return _M
