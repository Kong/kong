-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong = kong
local ngx_md5 = ngx.md5
local ssl = require("ngx.ssl")

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
  return ngx_md5("kafka-upstream:cert:" .. cert_id)
end

local function load_certificate(cert_id)
  kong.log.debug("Looking for certificate id: ", cert_id)

  local certificate, err = kong.cache:get(cert_id_cache_key(cert_id), nil, load_cert, cert_id)
  if not certificate then
    kong.log.err("failed to find certificate: ", err)
    return nil, "failed to find certificate " .. cert_id
  end

  local cert, priv_key, err

  cert, err = ssl.parse_pem_cert(certificate.cert)
  if not cert then
    kong.log.err("failed to parse certificate: ", err)
    return nil, "failed to parse pem cert " .. err
  end

  priv_key, err = ssl.parse_pem_priv_key(certificate.key)
  if not priv_key then
    kong.log.err("failed to parse private key: ", err)
    return nil, "failed to parse private key"
  end

  return {
    cert,
    priv_key
  }
end

return {
  load_certificate = load_certificate
}
