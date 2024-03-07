-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--- Copyright 2019 Kong Inc.

local ngx = ngx
local kong = kong
local set_header = kong.service.request.set_header
local ngx_var = ngx.var
local meta = require "kong.meta"


local TLSMetadataHandler = {
  -- execute after the tls-handshake-modifier plugin which requests the client cert
  PRIORITY = 996,
  VERSION = meta.core_version
}

function TLSMetadataHandler:access(conf)

  if conf.inject_client_cert_details then

    if ngx.var.ssl_client_escaped_cert then
      -- add http headers
      set_header(conf.client_cert_header_name,
        ngx_var.ssl_client_escaped_cert)

      set_header(conf.client_serial_header_name,
        ngx_var.ssl_client_serial)

      set_header(conf.client_cert_issuer_dn_header_name,
        ngx_var.ssl_client_i_dn)

      set_header(conf.client_cert_subject_dn_header_name,
      ngx_var.ssl_client_s_dn)

      set_header(conf.client_cert_fingerprint_header_name,
        ngx_var.ssl_client_fingerprint)

    else
      kong.log.err("plugin enabled to inject tls client certificate headers, but " ..
        "no client certificate was provided")
    end

  end

end

return TLSMetadataHandler
