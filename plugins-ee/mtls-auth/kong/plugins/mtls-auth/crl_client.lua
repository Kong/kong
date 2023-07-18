-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local http = require "resty.http"
local socket_url = require "socket.url"
local openssl_x509_store = require("resty.openssl.x509.store")
local verify_flags = openssl_x509_store.verify_flags
local flags = verify_flags.X509_V_FLAG_PARTIAL_CHAIN +
        verify_flags.X509_V_FLAG_CRL_CHECK

local _M = {}

local function validate_protocol(host_url)
  local parsed_url = socket_url.parse(host_url)
  if parsed_url.scheme ~= "http" and parsed_url.scheme ~= "https" then
    return nil, "non supported protocol for CRL URL"
  end

  return host_url
end


local function get_and_validate_crl_url(cert)
  local crl_url, err = cert:get_crl_url()
  if err or not crl_url then
    return false, err
  end

  return validate_protocol(crl_url)
end

function _M.validate_cert(conf, proof_chain, store)
  -- get the CRL url
  local crl_url, err = get_and_validate_crl_url(proof_chain[1])
  if err or not crl_url then
    return nil, err
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
  local res, err = c:request_uri(crl_url, {
    method = "GET",
    proxy_opts = proxy_opts,
  })
  if not res then
    return nil, err
  end

  local http_status = res.status
  if http_status ~= 200 then
    return nil, "CRL request returns bad HTTP status code " .. http_status
  end

  local crl = res.body or ""
  -- do not enforce format here, most likely CA provider gives CRL in DER format
  -- but there might be exceptions
  local crl, err = require("resty.openssl.x509.crl").new(crl)
  if not crl then
    return nil, err
  end

  store:add(crl, true)

  local res, err = store:check_revocation(proof_chain)
  if res then
    return true
  else
    -- fallback to call store:verify if check_revocation isn't supported
    if err == "x509.store:check_revocation: this API is not supported in BoringSSL"
      or err == "x509.store:check_revocation: this API is supported from OpenSSL 1.1.0" then
      res, err = store:verify(proof_chain[1], proof_chain, false, nil, nil, flags)
      if res then
        return true
      end
    end
    return false, err
  end
end

return _M
