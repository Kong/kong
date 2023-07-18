-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ocsp = require "ngx.ocsp"
local http = require "resty.http"

local _M = {}

function _M.validate_cert(conf, proof_chain)
  local der_cert_chain = ""
  -- the client cert and its issuer are enough
  for i = 1, 2 do
    der_cert_chain = der_cert_chain .. proof_chain[i]:tostring("DER")
  end

  local ocsp_url, err = ocsp.get_ocsp_responder_from_der_chain(der_cert_chain)
  if not ocsp_url then
    return nil, err
  end

  local ocsp_req, err = ocsp.create_ocsp_request(der_cert_chain)
  if not ocsp_req then
    return nil, "failed to create OCSP request: " .. err
  end

  local proxy_opts = {}
  if conf.http_proxy_host then
    kong.log.debug("http_proxy is enabled; ", "http://", conf.http_proxy_host, ":",conf.http_proxy_port)
    proxy_opts.http_proxy = "http://"..conf.http_proxy_host..":"..conf.http_proxy_port
  end
  if conf.https_proxy_host then
    kong.log.debug("https_proxy is enabled; ", "http://", conf.https_proxy_host, ":",conf.https_proxy_port)
    proxy_opts.https_proxy = "http://"..conf.https_proxy_host..":"..conf.https_proxy_port
  end

  local c = http.new()
  c:set_timeout(conf.http_timeout)
  local res, err = c:request_uri(ocsp_url, {
    headers = {
      ["Content-Type"] = "application/ocsp-request"
    },
    method = "POST",
    body = ocsp_req,
    proxy_opts = proxy_opts,
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
