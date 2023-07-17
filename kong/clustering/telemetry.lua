-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local semaphore = require("ngx.semaphore")
local ws_server = require("resty.websocket.server")
local ws_client = require("resty.websocket.client")
local cjson = require("cjson.safe")
local constants = require("kong.constants")
local declarative = require("kong.db.declarative")
local utils = require("kong.tools.utils")
local clustering_utils = require("kong.clustering.utils")


local assert = assert
local pairs = pairs
local ipairs = ipairs
local sub = string.sub
local table_insert = table.insert
local table_remove = table.remove
local cjson_decode = cjson.decode
local inflate_gzip = utils.inflate_gzip
local deflate_gzip = utils.deflate_gzip


local kong = kong
local ngx = ngx
local ngx_ERR = ngx.ERR
local ngx_var = ngx.var
local ngx_exit = ngx.exit
local ngx_log = ngx.log
local ngx_WARN = ngx.WARN
local ngx_NOTICE = ngx.NOTICE
local ngx_DEBUG = ngx.DEBUG
local exiting = ngx.worker.exiting


local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH
local _log_prefix = "[clustering] "


local server_on_message_callbacks = {}
local MAX_PAYLOAD = kong.configuration.cluster_max_payload
local WS_OPTS = {
  timeout = constants.CLUSTERING_TIMEOUT,
  max_payload_len = MAX_PAYLOAD,
}


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
local function ws_event_loop(ws, on_connection, on_error, on_message, cbs_args)
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
        ngx.log(ngx.INFO, "error while receiving frame from peer: ", err)
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
            local _, err = cb(
              data,
              queued_send,
              cbs_args.on_message.node_id,
              cbs_args.on_message.node_hostname
            )
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
    client_cert = self.cert.cdata,
    client_priv_key = self.cert_key,
    server_name = server_name,
  }

  local conf = kong and kong.configuration or {}
  if conf.cluster_use_proxy then
    local proxy_opts = clustering_utils.parse_proxy_url(conf)
    opts.proxy_opts = {
      wss_proxy = proxy_opts.proxy_url,
      wss_proxy_authorization = proxy_opts.proxy_authorization,
    }

    ngx_log(ngx_DEBUG, _log_prefix,
            "using proxy ", proxy_opts.proxy_url, " to connect telemetry")
  end

  local res, err = c:connect(uri, opts)
  if not res then
    local delay = math.random(5, 10)

    ngx_log(ngx_ERR, "connection to control plane ", uri, " broken: ", err,
            " retrying after ", delay , " seconds")

    assert(reconnect(delay))
    return
  end

  local queued_send, wait = ws_event_loop(c, nil, nil, on_message)

  if on_connection then
    local _, err = on_connection(true, queued_send)
    if err then
      ngx_log(ngx_ERR, "error when executing on_connection function: ", err)
    end
  end

  wait()

  if c.close and not c.closed then
    c:close()
  end

  if on_connection then
    local _, err = on_connection(false)
    if err then
      ngx_log(ngx_ERR, "error when executing on_connection function: ", err)
    end
  end

  -- reconnect to the control plane in case of disconnection
  assert(reconnect(9 + math.random()))
end


local function handle_cp_websocket()
  local node_id = ngx_var.arg_node_id
  local node_hostname = ngx_var.arg_node_hostname
  if not (node_id and node_hostname) then
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
    current_on_message_callbacks,
    {
      on_message = {
        node_id = node_id,
        host_name = node_hostname,
      },
    }
  )

  wait()
end


local function register_server_on_message(typ, cb)
  if not server_on_message_callbacks[typ] then
    server_on_message_callbacks[typ] = { cb }
  else
    table_insert(server_on_message_callbacks[typ], cb)
  end
end


return {
  telemetry_communicate = telemetry_communicate,
  handle_cp_websocket = handle_cp_websocket,
  register_server_on_message = register_server_on_message,
}
