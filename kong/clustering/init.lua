-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}

local constants = require("kong.constants")
local clustering_utils = require("kong.clustering.utils")
local version_negotiation = require("kong.clustering.version_negotiation")
local pl_file = require("pl.file")
local pl_tablex = require("pl.tablex")
local ws_server = require("resty.websocket.server")
local ws_client = require("resty.websocket.client")
local ssl = require("ngx.ssl")
local openssl_x509 = require("resty.openssl.x509")
local isempty = require("table.isempty")
local isarray = require("table.isarray")
local nkeys = require("table.nkeys")
local new_tab = require("table.new")
local ngx_null = ngx.null
local ngx_md5 = ngx.md5
local ngx_md5_bin = ngx.md5_bin
local tostring = tostring
local assert = assert
local error = error
local concat = table.concat
local pairs = pairs
local sort = table.sort
local type = type
local sub = string.sub

local check_for_revocation_status = clustering_utils.check_for_revocation_status

-- XXX EE
local semaphore = require("ngx.semaphore")
local cjson = require("cjson.safe")
local utils = require("kong.tools.utils")
local declarative = require("kong.db.declarative")
local assert = assert
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


local MT = { __index = _M, }


local function to_sorted_string(value)
  if value == ngx_null then
    return "/null/"
  end

  local t = type(value)
  if t == "string" or t == "number" then
    return value

  elseif t == "boolean" then
    return tostring(value)

  elseif t == "table" then
    if isempty(value) then
      return "{}"

    elseif isarray(value) then
      local count = #value
      if count == 1 then
        return to_sorted_string(value[1])

      elseif count == 2 then
        return to_sorted_string(value[1]) .. ";" ..
               to_sorted_string(value[2])

      elseif count == 3 then
        return to_sorted_string(value[1]) .. ";" ..
               to_sorted_string(value[2]) .. ";" ..
               to_sorted_string(value[3])

      elseif count == 4 then
        return to_sorted_string(value[1]) .. ";" ..
               to_sorted_string(value[2]) .. ";" ..
               to_sorted_string(value[3]) .. ";" ..
               to_sorted_string(value[4])

      elseif count == 5 then
        return to_sorted_string(value[1]) .. ";" ..
               to_sorted_string(value[2]) .. ";" ..
               to_sorted_string(value[3]) .. ";" ..
               to_sorted_string(value[4]) .. ";" ..
               to_sorted_string(value[5])
      end

      local i = 0
      local o = new_tab(count < 100 and count or 100, 0)
      for j = 1, count do
        i = i + 1
        o[i] = to_sorted_string(value[j])

        if j % 100 == 0 then
          i = 1
          o[i] = ngx_md5_bin(concat(o, ";", 1, 100))
        end
      end

      return ngx_md5_bin(concat(o, ";", 1, i))

    else
      local count = nkeys(value)
      local keys = new_tab(count, 0)
      local i = 0
      for k in pairs(value) do
        i = i + 1
        keys[i] = k
      end

      sort(keys)

      local o = new_tab(count, 0)
      for i = 1, count do
        o[i] = keys[i] .. ":" .. to_sorted_string(value[keys[i]])
      end

      value = concat(o, ";", 1, count)

      return #value > 512 and ngx_md5_bin(value) or value
    end

  else
    error("invalid type to be sorted (JSON types are supported)")
  end
end


function _M.new(conf)
  assert(conf, "conf can not be nil", 2)

  local self = {
    conf = conf,
  }

  setmetatable(self, MT)

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

  --- XXX EE: needed for encrypting config cache at the rest
  -- this will be used at init_worker()
  if conf.role == "data_plane" and conf.data_plane_config_cache_mode == "encrypted" then
    self.cert_public = cert:get_pubkey()
    self.cert_private = key
  end
  --- EE

  if conf.role == "control_plane" then
    self.json_handler = require("kong.clustering.control_plane").new(self)
    self.wrpc_handler = require("kong.clustering.wrpc_control_plane").new(self)
  end


  return self
end


function _M:calculate_config_hash(config_table)
  if type(config_table) ~= "table" then
    local config_hash = ngx_md5(to_sorted_string(config_table))
    return config_hash, { config = config_hash }
  end

  local routes    = config_table.routes
  local services  = config_table.services
  local plugins   = config_table.plugins
  local upstreams = config_table.upstreams
  local targets   = config_table.targets

  local routes_hash    = routes    and ngx_md5(to_sorted_string(routes))    or DECLARATIVE_EMPTY_CONFIG_HASH
  local services_hash  = services  and ngx_md5(to_sorted_string(services))  or DECLARATIVE_EMPTY_CONFIG_HASH
  local plugins_hash   = plugins   and ngx_md5(to_sorted_string(plugins))   or DECLARATIVE_EMPTY_CONFIG_HASH
  local upstreams_hash = upstreams and ngx_md5(to_sorted_string(upstreams)) or DECLARATIVE_EMPTY_CONFIG_HASH
  local targets_hash   = targets   and ngx_md5(to_sorted_string(targets))   or DECLARATIVE_EMPTY_CONFIG_HASH

  config_table.routes    = nil
  config_table.services  = nil
  config_table.plugins   = nil
  config_table.upstreams = nil
  config_table.targets   = nil

  local config_hash = ngx_md5(to_sorted_string(config_table) .. routes_hash
                                                             .. services_hash
                                                             .. plugins_hash
                                                             .. upstreams_hash
                                                             .. targets_hash)

  config_table.routes    = routes
  config_table.services  = services
  config_table.plugins   = plugins
  config_table.upstreams = upstreams
  config_table.targets   = targets

  return config_hash, {
    config    = config_hash,
    routes    = routes_hash,
    services  = services_hash,
    plugins   = plugins_hash,
    upstreams = upstreams_hash,
    targets   = targets_hash,
  }
end

local function fill_empty_hashes(hashes)
  for _, field_name in ipairs{
    "config",
    "routes",
    "services",
    "plugins",
    "upstreams",
    "targets",
  } do
    hashes[field_name] = hashes[field_name] or DECLARATIVE_EMPTY_CONFIG_HASH
  end
end

function _M:request_version_negotiation()
  local response_data, err = version_negotiation.request_version_handshake(self.conf, self.cert, self.cert_key)
  if not response_data then
    ngx_log(ngx_ERR, _log_prefix, "error while requesting version negotiation: " .. err)
    assert(ngx.timer.at(math.random(5, 10), function(premature)
      self:communicate(premature)
    end))
    return
  end
end


function _M:update_config(config_table, config_hash, update_cache, hashes)
  assert(type(config_table) == "table")

  if not config_hash then
    config_hash, hashes = self:calculate_config_hash(config_table)
  end

  if hashes then
    fill_empty_hashes(hashes)
  end

  local current_hash = declarative.get_current_hash()
  if current_hash == config_hash then
    ngx_log(ngx_DEBUG, _log_prefix, "same config received from control plane, ",
      "no need to reload")
    return true
  end

  local entities, err, _, meta, new_hash =
  self.declarative_config:parse_table(config_table, config_hash)
  if not entities then
    return nil, "bad config received from control plane " .. err
  end

  if current_hash == new_hash then
    ngx_log(ngx_DEBUG, _log_prefix, "same config received from control plane, ",
      "no need to reload")
    return true
  end

  -- NOTE: no worker mutex needed as this code can only be
  -- executed by worker 0

  local res
  res, err = declarative.load_into_cache_with_events(entities, meta, new_hash, hashes)
  if not res then
    return nil, err
  end

  if update_cache and self.config_cache then
    -- local persistence only after load finishes without error
    clustering_utils.save_config_cache(self, config_table)
  end

  return true
end


function _M:handle_cp_websocket()
  return self.json_handler:handle_cp_websocket()
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
  -- with cluster_mtls == "pki", always return true as in this mode we only check
  -- if client cert matches CA and it's already done by Nginx

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
      return ngx.thread.wait(recv, send)
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
end

function _M:handle_wrpc_websocket()
  return self.wrpc_handler:handle_cp_websocket()
end

function _M:serve_version_handshake()
  return version_negotiation.serve_version_handshake(self.conf, self.cert_digest)
end

function _M:init_worker()
  self.plugins_list = assert(kong.db.plugins:get_handlers())
  sort(self.plugins_list, function(a, b)
    return a.name:lower() < b.name:lower()
  end)

  self.plugins_list = pl_tablex.map(function(p)
    return { name = p.name, version = p.handler.VERSION, }
  end, self.plugins_list)

  local role = self.conf.role
  if role == "control_plane" then
    self.json_handler:init_worker()
    self.wrpc_handler:init_worker()
  end

  if role == "data_plane" and ngx.worker.id() == 0 then
    assert(ngx.timer.at(0, function(premature)
      if premature then
        return
      end

      self:request_version_negotiation()

      local config_proto, msg = version_negotiation.get_negotiated_service("config")
      if not config_proto and msg then
        ngx_log(ngx_ERR, _log_prefix, "error reading negotiated \"config\" service: ", msg)
      end

      ngx_log(ngx_DEBUG, _log_prefix, "config_proto: ", config_proto, " / ", msg)
      if config_proto == "v1" then
        self.child = require "kong.clustering.wrpc_data_plane".new(self)

      elseif config_proto == "v0" or config_proto == nil then
        self.child = require "kong.clustering.data_plane".new(self)
      end

      --- XXX EE: clear private key as it is not needed after this point
      self.cert_private = nil
      --- EE

      if self.child then
        if self.child.config_cache then
          clustering_utils.load_config_cache(self.child)
        end
        self.child:communicate()
      end

    end))
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
