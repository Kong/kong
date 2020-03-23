local ssl = require "ngx.ssl"
local ocsp = require "ngx.ocsp"
local http = require "resty.http"
local kong = kong

local _M = {}

function _M.validate_cert(conf, cert_chain)
  local der_cert_chain, err = ssl.cert_pem_to_der(cert_chain)
  if not der_cert_chain then
    return nil, "failed to convert certificate chain from PEM to DER: " .. err
  end

  local ocsp_url, err = ocsp.get_ocsp_responder_from_der_chain(der_cert_chain)
  if not ocsp_url then
    return nil, err
  end

  local ocsp_req, err = ocsp.create_ocsp_request(der_cert_chain)
  if not ocsp_req then
    return nil, "failed to create OCSP request: " .. err
  end
  local c = http.new()
  local res, err = c:request_uri(ocsp_url, {
    headers = {
      ["Content-Type"] = "application/ocsp-request"
    },
    timeout = conf.http_timeout,
    method = "POST",
    body = ocsp_req,
  })

  if not res then
    return nil, err
  end

  local http_status = res.status
  if http_status ~= 200 then
    return nil, "OCSP responder returns bad HTTP status code " .. http_status
  end

  local ocsp_resp = res.body
  if ocsp_resp and #ocsp_resp > 0 then
    local ok, err = ocsp.validate_ocsp_response(ocsp_resp, der_cert_chain)
    if not ok then
      return false, "failed to validate OCSP response: " .. err
    end

    ok, err = ocsp.set_ocsp_status_resp(ocsp_resp)
    if not ok then
      return false, err
    end
  end

  return true
end

return _M