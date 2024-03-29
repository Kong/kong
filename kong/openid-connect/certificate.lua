-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local openssl_x509  = require "resty.openssl.x509"
local ngx_ssl       = require "ngx.ssl"

local parse_pem_cert     = ngx_ssl.parse_pem_cert
local parse_pem_priv_key = ngx_ssl.parse_pem_priv_key


local load_certificate, load_key
do
  function load_certificate(c)
    local cert, err = parse_pem_cert(c)
    if not cert then
      return nil, err
    end

    local digest = openssl_x509.new(c):digest("sha256")
    if not digest then
      return nil, "cannot create digest value of certificate"
    end

    return cert, nil, digest
  end

  function load_key(k)
    local key, err = parse_pem_priv_key(k)
    if not key then
      return nil, err
    end

    return key
  end
end


local certificate = {
  load_certificate = load_certificate,
  load_key         = load_key,
}


return certificate
