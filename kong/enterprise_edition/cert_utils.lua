-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ssl      = require("ngx.ssl")
local lrucache = require("resty.lrucache").new(200)

local kong    = kong
local sha256_hex = require "kong.tools.sha256".sha256_hex

local function load_cert(cert_id)
  kong.log.debug("cache miss for CA store")

  local key = {
    id = cert_id
  }

  local obj, err = kong.db.certificates:select(key)
  if not obj then
    if err then
      kong.log.notice("failed to select certificate with key: ", key)
      return nil, err
    end

    return nil, "Certificate '" .. tostring(cert_id) .. "' does not exist"
  end

  return obj
end

local function cert_id_cache_key(cert_id)
  return sha256_hex("kafka-upstream:cert:" .. cert_id)
end

local function load_certificate(cert_id)
  kong.log.debug("Looking for certificate id: ", cert_id)

  local cert_cache_key = cert_id_cache_key(cert_id)

  local certificate, err = kong.cache:get(cert_cache_key, nil, load_cert, cert_id)
  if not certificate then
    kong.log.err("failed to find certificate: ", err)
    return nil, nil, "failed to find certificate " .. cert_id
  end

  local cert, priv_key, key_err, cert_err

  local parsed_cert_cache_key = cert_cache_key .. ":parsed_cert"
  local parsed_priv_key_cache_key = cert_cache_key .. ":parsed_priv_key"

  cert = lrucache:get(parsed_cert_cache_key)
  if not cert then
    cert, cert_err = ssl.parse_pem_cert(certificate.cert)
    if cert == nil then
      kong.log.err("failed to parse certificate: ", cert_err)
      return nil, nil, "failed to parse pem cert " .. cert_err
    end
    lrucache:set(parsed_cert_cache_key, cert)
  end

  priv_key = lrucache:get(parsed_priv_key_cache_key)
  if not priv_key then
    priv_key, key_err = ssl.parse_pem_priv_key(certificate.key)
    if priv_key == nil then
      kong.log.err("failed to parse private key: ", key_err)
      return cert, nil, "failed to parse private key" .. key_err
    end
    lrucache:set(parsed_priv_key_cache_key, priv_key)
  end

  return cert, priv_key, nil
end

return {
  load_certificate = load_certificate
}
