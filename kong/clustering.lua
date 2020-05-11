local _M = {}


local semaphore = require("ngx.semaphore")
local ws_client = require("resty.websocket.client")
local ws_server = require("resty.websocket.server")
local ssl = require("ngx.ssl")
local cjson = require("cjson.safe")
local declarative = require("kong.db.declarative")
local utils = require("kong.tools.utils")
local openssl_x509 = require("resty.openssl.x509")
local assert = assert
local setmetatable = setmetatable
local type = type
local ipairs = ipairs
local ngx_log = ngx.log
local ngx_sleep = ngx.sleep
local cjson_decode = cjson.decode
local cjson_encode = cjson.encode
local kong = kong
local ngx_exit = ngx.exit
local exiting = ngx.worker.exiting
local ngx_time = ngx.time
local new_tab = require("table.new")
local ngx_var = ngx.var
local io_open = io.open
local table_insert = table.insert
local table_remove = table.remove
local inflate_gzip = utils.inflate_gzip
local deflate_gzip = utils.deflate_gzip


local MAX_PAYLOAD = 4 * 1024 * 1024 -- 4MB
local PING_INTERVAL = 30 -- 30 seconds
local WS_OPTS = {
  max_payload_len = MAX_PAYLOAD,
}
local ngx_ERR = ngx.ERR
local ngx_DEBUG = ngx.DEBUG
local ngx_INFO = ngx.INFO
local WEAK_KEY_MT = { __mode = "k", }
local CERT_DIGEST
local CERT, CERT_KEY
local clients = setmetatable({}, WEAK_KEY_MT)
local shdict = ngx.shared.kong_clustering -- only when role == "control_plane"
local prefix = ngx.config.prefix()
local CONFIG_CACHE = prefix .. "/config.cache.json.gz"
local RECONFIGURE_TYPE_KEY = "reconfigure"
local declarative_config

local server_on_message_callbacks = {}

local function update_config(config_table, update_cache)
  assert(type(config_table) == "table")

  if not declarative_config then
    declarative_config = declarative.new_config(kong.configuration)
  end

  local entities, err, _, meta, new_hash = declarative_config:parse_table(config_table)
  if not entities then
    return nil, "bad config received from control plane " .. err
  end

  if declarative.get_current_hash() == new_hash then
    ngx_log(ngx_DEBUG, "same config received from control plane,",
            "no need to reload")
    return true
  end

  -- NOTE: no worker mutex needed as this code can only be
  -- executed by worker 0
  local res, err =
    declarative.load_into_cache_with_events(entities, meta, new_hash)
  if not res then
    return nil, err
  end

  if update_cache then
    -- local persistence only after load finishes without error
    local f, err = io_open(CONFIG_CACHE, "w")
    if not f then
      ngx_log(ngx_ERR, "unable to open cache file: ", err)

    else
      local res
      res, err = f:write(assert(deflate_gzip(cjson_encode(config_table))))
      if not res then
        ngx_log(ngx_ERR, "unable to write cache file: ", err)
      end

      f:close()
    end
  end

  return true
end


local function send_ping(c)
  local _, err = c:send_ping(declarative.get_current_hash())
  if err then
    ngx_log(ngx_ERR, "unable to ping control plane node: ", err)
    -- return and let the main thread handle the error
    return nil
  end

  ngx_log(ngx_DEBUG, "sent PING packet to control plane")

  return true
end

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
    return ngx.thread.wait(recv, send)
  end

  return queued_send, wait

end


local function communicate(premature, uri, server_name, on_connection, on_message)
  if premature then
    -- worker wants to exit
    return
  end

  local reconnect = function(delay)
    return ngx.timer.at(delay, communicate, uri, server_name, on_connection, on_message)
  end

  local c = assert(ws_client:new(WS_OPTS))

  local opts = {
    ssl_verify = true,
    client_cert = CERT,
    client_priv_key = CERT_KEY,
    server_name = server_name,
  }

  local res, err = c:connect(uri, opts)
  if not res then
    local delay = math.random(5, 10)

    ngx_log(ngx_ERR, "connection to control plane broken: ", err,
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

_M.communicate = communicate


local function validate_shared_cert()
  local cert = ngx_var.ssl_client_raw_cert

  if not cert then
    ngx_log(ngx_ERR, "Data Plane failed to present client certificate " ..
                     "during handshake")
    return ngx_exit(444)
  end

  cert = assert(openssl_x509.new(cert, "PEM"))
  local digest = assert(cert:digest("sha256"))

  if digest ~= CERT_DIGEST then
    ngx_log(ngx_ERR, "Data Plane presented incorrect client certificate " ..
                     "during handshake, expected digest: " .. CERT_DIGEST ..
                     " got: " .. digest)
    return ngx_exit(444)
  end
end


function _M.handle_cp_websocket(is_telemetry)
  -- use mutual TLS authentication
  if kong.configuration.cluster_mtls == "shared" then
    validate_shared_cert()
  end

  local node_id = ngx_var.arg_node_id
  if not node_id then
    ngx_exit(400)
  end

  local node_hostname = ngx_var.arg_node_hostname
  local node_ip = ngx_var.remote_addr

  local wb, err = ws_server:new(WS_OPTS)
  if not wb then
    ngx_log(ngx_ERR, "failed to perform server side WebSocket handshake: ", err)
    return ngx_exit(444)
  end

  local current_on_message_callbacks = {}
  for k, v in pairs(server_on_message_callbacks) do
    current_on_message_callbacks[k] = v
  end

  if not is_telemetry then
    current_on_message_callbacks["ping"] = {
      function(data, queued_send)
        queued_send("PONG")

        local ok
        ok, err = shdict:safe_set(node_id,
                                  cjson_encode({
                                    last_seen = ngx_time(),
                                    config_hash =
                                      data ~= "" and data or nil,
                                    hostname = node_hostname,
                                    ip = node_ip,
                                  }), PING_INTERVAL * 2 + 5)
        if not ok then
          ngx_log(ngx_ERR, "unable to update in-memory cluster status: ", err)
        end
      end
    }
  end

  local queued_send, wait = ws_event_loop(wb,
    nil,
    function(_)
      return ngx_exit(ngx_ERR)
    end,
    current_on_message_callbacks)

  if not is_telemetry then
    -- is a config sync client
    clients[wb] = queued_send

    local res
    -- unconditionally send config update to new clients to
    -- ensure they have latest version running
    res, err = declarative.export_config()
    if not res then
      ngx_log(ngx_ERR, "unable to export config from database: ".. err)
    end

    local payload = cjson_encode({ type = RECONFIGURE_TYPE_KEY,
                                   config_table = res,
                                 })
    queued_send(payload)
  end

  wait()
end


function _M.get_status()
  local result = new_tab(0, 8)

  for _, n in ipairs(shdict:get_keys()) do
    result[n] = cjson_decode(shdict:get(n))
  end


  return result
end


local function push_config(config_table)
  local payload = cjson_encode({ type = RECONFIGURE_TYPE_KEY,
                                 config_table = config_table,
                               })

  local n = 0

  for _, queued_send in pairs(clients) do
    queued_send(payload)

    n = n + 1
  end

  ngx_log(ngx_DEBUG, "config pushed to ", n, " clients")
end


local function init_mtls(conf)
  local f, err = io_open(conf.cluster_cert, "r")
  if not f then
    return nil, "unable to open cluster cert file: " .. err
  end

  local cert
  cert, err = f:read("*a")
  if not cert then
    f:close()
    return nil, "unable to read cluster cert file: " .. err
  end

  f:close()

  CERT, err = ssl.parse_pem_cert(cert)
  if not CERT then
    return nil, err
  end

  cert = openssl_x509.new(cert, "PEM")

  CERT_DIGEST = cert:digest("sha256")

  f, err = io_open(conf.cluster_cert_key, "r")
  if not f then
    return nil, "unable to open cluster cert key file: " .. err
  end

  local key
  key, err = f:read("*a")
  if not key then
    f:close()
    return nil, "unable to read cluster cert key file: " .. err
  end

  f:close()

  CERT_KEY, err = ssl.parse_pem_priv_key(key)
  if not CERT_KEY then
    return nil, err
  end

  return true
end


function _M.init(conf)
  assert(conf, "conf can not be nil", 2)

  if conf.role == "data_plane" or conf.role == "control_plane" then
    assert(init_mtls(conf))
  end
end


local function start_conf_sync_client(conf)
  -- TODO: pick one random CP
  local address = conf.cluster_control_plane

  local uri = "wss://" .. address .. "/v1/outlet?node_id=" ..
              kong.node.get_id() .. "&node_hostname=" .. utils.get_hostname()
  local server_name
  if conf.cluster_mtls == "shared" then
    server_name = "kong_clustering"
  else
    -- server_name will be set to the host if it is not explicitly defined here
    if conf.cluster_server_name ~= "" then
      server_name = conf.cluster_server_name
    end
  end

  local on_message = {
    [RECONFIGURE_TYPE_KEY] = {
      function(msg, queued_send)
        local config_table = assert(msg.config_table)

        local res, err = update_config(config_table, true)
        if not res then
          ngx_log(ngx_ERR, "unable to update running config: ", err)
        end

        queued_send("PING")
      end,
    }
  }

  local ping_thread_cookie

  local on_connection = function(connected, queued_send)
    if not connected then
      return
    end
    ping_thread_cookie = utils.uuid()

    ngx.thread.spawn(function(cookie)
      -- make sure the old thread clean up by itself
      while cookie == ping_thread_cookie do
        queued_send("PING")

        ngx_sleep(PING_INTERVAL)
      end
    end, ping_thread_cookie)
  end

  assert(ngx.timer.at(0, communicate, uri, server_name, on_connection, on_message))
end


function _M.init_worker(conf)
  assert(conf, "conf can not be nil", 2)

  if conf.role == "data_plane" then
    -- ROLE = "data_plane"

    if ngx.worker.id() == 0 then
      local f = io_open(CONFIG_CACHE, "r")
      if f then
        local config, err = f:read("*a")
        if not config then
          ngx_log(ngx_ERR, "unable to read cached config file: ", err)
        end

        f:close()

        if config then
          ngx_log(ngx_INFO, "found cached copy of data-plane config, loading..")

          local err

          config, err = inflate_gzip(config)
          if config then
            config = cjson_decode(config)

            if config then
              local res
              res, err = update_config(config, false)
              if not res then
                ngx_log(ngx_ERR, "unable to running config from cache: ", err)
              end
            end

          else
            ngx_log(ngx_ERR, "unable to inflate cached config: ",
                    err, ", ignoring...")
          end
        end
      end

      start_conf_sync_client(conf)

    end

  elseif conf.role == "control_plane" then
    assert(shdict, "kong_clustering shdict missing")

    -- ROLE = "control_plane"

    kong.worker_events.register(function(data)
      -- we have to re-broadcast event using `post` because the dao
      -- events were sent using `post_local` which means not all workers
      -- can receive it
      local res, err = kong.worker_events.post("clustering", "push_config")
      if not res then
        ngx_log(ngx_ERR, "unable to broadcast event: " .. err)
      end
    end, "dao:crud")

    kong.worker_events.register(function(data)
      local res, err = declarative.export_config()
      if not res then
        ngx_log(ngx_ERR, "unable to export config from database: " .. err)
      end

      push_config(res)
    end, "clustering", "push_config")
  end
end

function _M.register_server_on_message(typ, cb)
  if not server_on_message_callbacks[typ] then
    server_on_message_callbacks[typ] = { cb }
  else
    table.insert(server_on_message_callbacks[typ], cb)
  end
end


return _M
