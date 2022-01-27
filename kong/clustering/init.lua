-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}


local pl_file = require("pl.file")
local pl_tablex = require("pl.tablex")
local ws_server = require("resty.websocket.server")
local ws_client = require("resty.websocket.client")
local ssl = require("ngx.ssl")
local http = require("resty.http")
local openssl_x509 = require("resty.openssl.x509")
local ngx_null = ngx.null
local ngx_md5 = ngx.md5
local tostring = tostring
local assert = assert
local error = error
local concat = table.concat
local sort = table.sort
local type = type

-- XXX EE
local semaphore = require("ngx.semaphore")
local cjson = require("cjson.safe")
local utils = require("kong.tools.utils")
local constants = require("kong.constants")
local declarative = require("kong.db.declarative")
local assert = assert
local setmetatable = setmetatable
local ngx = ngx
local ngx_log = ngx.log
local ngx_WARN = ngx.WARN
local ngx_var = ngx.var
local ngx_NOTICE = ngx.NOTICE
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
local OCSP_TIMEOUT = constants.CLUSTERING_OCSP_TIMEOUT

local MT = { __index = _M, }


local compare_sorted_strings


local function to_sorted_string(value)
  if value == ngx_null then
    return "/null/"
  end

  local t = type(value)
  if t == "table" then
    local i = 1
    local o = { "{" }
    for k, v in pl_tablex.sort(value, compare_sorted_strings) do
      o[i+1] = to_sorted_string(k)
      o[i+2] = ":"
      o[i+3] = to_sorted_string(v)
      o[i+4] = ";"
      i=i+4
    end
    if i == 1 then
      i = i + 1
    end
    o[i] = "}"

    return concat(o, nil, 1, i)

  elseif t == "string" then
    return "$" .. value .. "$"

  elseif t == "number" then
    return "#" .. tostring(value) .. "#"

  elseif t == "boolean" then
    return "?" .. tostring(value) .. "?"

  else
    error("invalid type to be sorted (JSON types are supported")
  end
end


compare_sorted_strings = function(a, b)
  a = to_sorted_string(a)
  b = to_sorted_string(b)
  return a < b
end


function _M.new(conf)
  assert(conf, "conf can not be nil", 2)

  local self = {
    conf = conf,
  }

  setmetatable(self, MT)

  -- note: pl_file.read throws error on failure so
  -- no need for error checking
  local cert = pl_file.read(conf.cluster_cert)
  self.cert = assert(ssl.parse_pem_cert(cert))

  cert = openssl_x509.new(cert, "PEM")
  self.cert_digest = cert:digest("sha256")
  local _, cert_cn_parent = get_cn_parent_domain(cert)
  self.cert_cn_parent = cert_cn_parent

  local key = pl_file.read(conf.cluster_cert_key)
  self.cert_key = assert(ssl.parse_pem_priv_key(key))

  --- XXX EE: needed for encrypting config cache at the rest
  if conf.role == "data_plane" and conf.data_plane_config_cache_mode == "encrypted" then
    self.cert_public = cert:get_pubkey()
    self.cert_private = key
  end
  --- EE

  self.child = require("kong.clustering." .. conf.role).new(self)

  return self
end


function _M:calculate_config_hash(config_table)
  return ngx_md5(to_sorted_string(config_table))
end


function _M:handle_cp_websocket()
  return self.child:handle_cp_websocket()
end

local check_for_revocation_status
do
  local get_full_client_certificate_chain = require("resty.kong.tls").get_full_client_certificate_chain
  check_for_revocation_status = function()
    --- XXX EE: ensure the OCSP code path is isolated
    local ocsp = require("ngx.ocsp")
    --- EE
    local cert, err = get_full_client_certificate_chain()
    if not cert then
      return nil, err
    end

    local der_cert
    der_cert, err = ssl.cert_pem_to_der(cert)
    if not der_cert then
      return nil, "failed to convert certificate chain from PEM to DER: " .. err
    end

    local ocsp_url
    ocsp_url, err = ocsp.get_ocsp_responder_from_der_chain(der_cert)
    if not ocsp_url then
      return nil, err or "OCSP responder endpoint can not be determined, " ..
                         "maybe the client certificate is missing the " ..
                         "required extensions"
    end

    local ocsp_req
    ocsp_req, err = ocsp.create_ocsp_request(der_cert)
    if not ocsp_req then
      return nil, "failed to create OCSP request: " .. err
    end

    local c = http.new()
    local res
    res, err = c:request_uri(ocsp_url, {
      headers = {
        ["Content-Type"] = "application/ocsp-request"
      },
      timeout = OCSP_TIMEOUT,
      method = "POST",
      body = ocsp_req,
    })

    if not res then
      return nil, "failed sending request to OCSP responder: " .. tostring(err)
    end
    if res.status ~= 200 then
      return nil, "OCSP responder returns bad HTTP status code: " .. res.status
    end

    local ocsp_resp = res.body
    if not ocsp_resp or #ocsp_resp == 0 then
      return nil, "unexpected response from OCSP responder: empty body"
    end

    res, err = ocsp.validate_ocsp_response(ocsp_resp, der_cert)
    if not res then
      return false, "failed to validate OCSP response: " .. err
    end

    return true
  end
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
    local cn, cn_parent = get_cn_parent_domain(cert)
    if not cn then
      return false, "data plane presented incorrect client certificate " ..
                    "during handshake, unable to extract CN: " .. cn_parent

    elseif cn_parent ~= self.cert_cn_parent then
      return false, "data plane presented incorrect client certificate " ..
                    "during handshake, expected CN as subdomain of: " ..
                    self.cert_cn_parent .. " got: " .. cn
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


-- TODO make these 2 functions class members, so they can be used in data_plane
local function is_timeout(err)
  return err and string.sub(err, -7) == "timeout"
end

local function send_ping(c)
  local hash = declarative.get_current_hash()

  if hash == true then
    hash = string.rep("0", 32)
  end

  local _, err = c:send_ping(hash)
  if err then
    ngx_log(is_timeout(err) and ngx_NOTICE or ngx_WARN, "unable to ping control plane node: ", err)

  else
    ngx_log(ngx_DEBUG, "sent PING packet to control plane")
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

function _M:init_worker()
  self.plugins_list = assert(kong.db.plugins:get_handlers())
  sort(self.plugins_list, function(a, b)
    return a.name:lower() < b.name:lower()
  end)

  self.plugins_list = pl_tablex.map(function(p)
    return { name = p.name, version = p.handler.VERSION, }
  end, self.plugins_list)

  self.child:init_worker()
end

function _M.register_server_on_message(typ, cb)
  if not server_on_message_callbacks[typ] then
    server_on_message_callbacks[typ] = { cb }
  else
    table.insert(server_on_message_callbacks[typ], cb)
  end
end

return _M
