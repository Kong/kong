local _M = {}


local msgpack = require("MessagePack")
local ssl = require("ngx.ssl")
local ocsp = require("ngx.ocsp")
local http = require("resty.http")
local event_loop = require("kong.hybrid.event_loop")
local message = require("kong.hybrid.message")
local openssl_x509 = require("resty.openssl.x509")
local constants = require("kong.constants")


local mp_unpack = msgpack.unpack
local ngx_log = ngx.log
local ngx_exit = ngx.exit
local ngx_var = ngx.var
local ngx_header = ngx.header


local ngx_WARN = ngx.WARN
local ngx_ERR = ngx.ERR
local ngx_OK = ngx.OK
local TOPIC_BASIC_INFO = "basic_info"
local OCSP_TIMEOUT = constants.CLUSTERING_OCSP_TIMEOUT


function _M.new(parent)
  local self = {
    loop = event_loop.new("control_plane"),
  }

  return setmetatable(self, {
    __index = function(tab, key)
      return _M[key] or parent[key]
    end,
  })
end


function _M:validate_shared_cert()
  local cert = ngx_var.ssl_client_raw_cert

  if not cert then
    ngx_log(ngx_ERR, "[hybrid-comm] Data Plane failed to present " ..
                     "client certificate during handshake")
    return ngx_exit(444)
  end

  cert = assert(openssl_x509.new(cert, "PEM"))
  local digest = assert(cert:digest("sha256"))

  if digest ~= self.cert_digest then
    ngx_log(ngx_ERR, "[hybrid-comm] Data Plane presented incorrect "..
                     "client certificate during handshake, expected digest: " ..
                     self.cert_digest ..
                     " got: " .. digest)
    return ngx_exit(444)
  end
end

local check_for_revocation_status
do
  local get_full_client_certificate_chain = require("resty.kong.tls").get_full_client_certificate_chain
  check_for_revocation_status = function()
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


function _M:handle_cp_protocol()
  -- use mutual TLS authentication
  if self.conf.cluster_mtls == "shared" then
    self:validate_shared_cert()

  elseif self.conf.cluster_ocsp ~= "off" then
    local res, err = check_for_revocation_status()
    if res == false then
      ngx_log(ngx_ERR, "[hybrid-comm] DP client certificate was revoked: ", err)
      return ngx_exit(444)

    elseif not res then
      ngx_log(ngx_WARN, "[hybrid-comm] DP client certificate revocation check failed: ", err)
      if self.conf.cluster_ocsp == "on" then
        return ngx_exit(444)
      end
    end
  end

  ngx_header["Upgrade"] = "Kong-Hybrid/2"
  ngx_header["Content-Type"] = nil
  ngx.status = 101

  local ok, err = ngx.send_headers()
  if not ok then
    ngx_log(ngx_ERR, "[hybrid-comm] failed to send response header: " .. (err or "unknown"))
    return ngx_exit(500)
  end
  ok, err = ngx.flush(true)
  if not ok then
    ngx_log(ngx_ERR, "[hybrid-comm] failed to flush response header: " .. (err or "unknown"))
    return ngx_exit(500)
  end

  local sock = assert(ngx.req.socket(true))

  -- basic_info frame
  local m = message.unpack_from_socket(sock)
  assert(m.topic == TOPIC_BASIC_INFO)
  local basic_info = mp_unpack(m.message)

  local res, err = self.loop:handle_peer(basic_info.node_id, sock)

  if not res then
    ngx_log(ngx_ERR, err)
    return ngx_exit(ngx_ERR)
  end

  return ngx_exit(ngx_OK)
end


function _M:register_callback(topic, callback)
  return self.loop:register_callback(topic, callback)
end


function _M:send(message)
  return self.loop:send(message)
end


function _M:init_worker()
  -- role = "control_plane"
end

return _M
