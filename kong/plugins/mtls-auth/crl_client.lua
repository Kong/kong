-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local http = require "resty.http"
local kong = kong
local socket_url = require "socket.url"

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

function _M.validate_cert(conf, cert, intermidiate, store)
  -- get the CRL url
  local crl_url, err = get_and_validate_crl_url(cert)
  if err or not crl_url then
    return nil, err
  end

  local c = http.new()
  local res, err = c:request_uri(crl_url, {
    timeout = conf.http_timeout,
    method = "GET",
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
  store:add(crl)

  return store:verify(cert, intermidiate)
end

return _M