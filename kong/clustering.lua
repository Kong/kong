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


local MAX_PAYLOAD = 65536 -- 64KB
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
local CONFIG_CACHE = prefix .. "/config.cache.json"
local declarative_config


local function update_config(config_table, update_cache)
  assert(type(config_table) == "table")

  if not declarative_config then
    declarative_config = declarative.new_config(kong.configuration)
  end

  local entities, _, _, _, new_hash = declarative_config:parse_table(config_table)
  if not entities then
    return nil, "bad config received from control plane"
  end

  if declarative.get_current_hash() == new_hash then
    ngx_log(ngx_DEBUG, "same config received from control plane,",
            "no need to reload")
    return true
  end

  -- NOTE: no worker mutex needed as this code can only be
  -- executed by worker 0
  local res, err = declarative.load_into_cache_with_events(entities, new_hash)
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
      res, err = f:write(cjson_encode(config_table))
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


local function communicate(premature, conf)
  if premature then
    -- worker wants to exit
    return
  end

  -- TODO: pick one random CP
  local address = conf.cluster_control_plane

  local c = assert(ws_client:new(WS_OPTS))
  local uri = "wss://" .. address .. "/v1/outlet?node_id=" ..
              kong.node.get_id() .. "&node_hostname=" .. utils.get_hostname()
  local res, err = c:connect(uri, { ssl_verify = true,
                                    client_cert = CERT,
                                    client_priv_key = CERT_KEY,
                                    server_name = "kong_clustering",
                                  }
                            )
  if not res then
    local delay = math.random(5, 10)

    ngx_log(ngx_ERR, "connection to control plane broken: ", err,
            " retrying after ", delay , " seconds")
    assert(ngx.timer.at(delay, communicate, conf))
    return
  end

  -- connection established
  -- ping thread
  ngx.thread.spawn(function()
    while true do
      if not send_ping(c) then
        return
      end

      ngx_sleep(PING_INTERVAL)
    end
  end)

  while true do
    local data, typ, err = c:recv_frame()
    if err then
      ngx.log(ngx.ERR, "error while receiving frame from control plane: ", err)
      c:close()

      local delay = 9 + math.random()
      assert(ngx.timer.at(delay, communicate, conf))
      return
    end

    if typ == "binary" then
      local msg = assert(cjson_decode(data))

      if msg.type == "reconfigure" then
        local config_table = assert(msg.config_table)

        local res, err = update_config(config_table, true)
        if not res then
          ngx_log(ngx_ERR, "unable to update running config: ", err)
        end

        send_ping(c)

      end
    elseif typ == "pong" then
      ngx_log(ngx_DEBUG, "received PONG frame from control plane")
    end
  end
end


function _M.handle_cp_websocket()
  -- use mutual TLS authentication
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

  local sem = semaphore.new()
  local queue = { sem = sem, }
  clients[wb] = queue

  local res
  -- unconditionally send config update to new clients to
  -- ensure they have latest version running
  res, err = declarative.export_config()
  if not res then
    ngx_log(ngx_ERR, "unable to export config from database: ".. err)
  end

  table.insert(queue, res)
  queue.sem:post()

  -- connection established
  -- ping thread
  ngx.thread.spawn(function()
    while true do
      local data, typ, err = wb:recv_frame()
      if not data then
        ngx_log(ngx_ERR, "did not receive ping frame from data plane: ", err)
        return ngx_exit(ngx_ERR)
      end

      assert(typ == "ping")
      local _
      _, err = wb:send_pong()
      if err then
        ngx_log(ngx_ERR, "failed to send PONG back to data plane: ", err)
        return ngx_exit(ngx_ERR)
      end

      ngx_log(ngx_DEBUG, "sent PONG packet to control plane")

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
  end)

  while not exiting() do
    local ok, err = sem:wait(10)
    if ok then
      local config = table.remove(queue, 1)
      assert(config, "config queue can not be empty after semaphore returns")

      local _, err = wb:send_binary(cjson_encode({ type = "reconfigure",
                                                       config_table = config,
                                                     }))
      if err then
        ngx_log(ngx_ERR, "unable to send updated configuration to node: ", err)

      else
        ngx_log(ngx_DEBUG, "sent config update to node")
      end

    else -- not ok
      if err ~= "timeout" then
        ngx_log(ngx_ERR, "semaphore wait error: ", err)
      end
    end
  end
end


function _M.get_status()
  local result = new_tab(0, 8)

  for _, n in ipairs(shdict:get_keys()) do
    result[n] = cjson_decode(shdict:get(n))
  end


  return result
end


local function push_config(config_table)
  local n = 0

  for _, queue in pairs(clients) do
    table.insert(queue, config_table)
    queue.sem:post()

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
          config = cjson_decode(config)

          if config then
            local res
            res, err = update_config(config, false)
            if not res then
              ngx_log(ngx_ERR, "unable to running config from cache: ", err)
            end
          end
        end
      end

      assert(ngx.timer.at(0, communicate, conf))
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


return _M
