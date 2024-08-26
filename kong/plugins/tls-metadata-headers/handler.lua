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
local clear_header = kong.service.request.clear_header
local ngx_var = ngx.var
local meta = require "kong.meta"
local openssl_x509 = require "resty.openssl.x509"
local resty_kong_tls = require "resty.kong.tls"
local escape_uri = ngx.escape_uri
local ngx_re_match = ngx.re.match
local fmt = string.format
local to_hex = require "resty.string".to_hex


local TLSMetadataHandler = {
  -- execute after the tls-handshake-modifier plugin which requests the client cert
  PRIORITY = 996,
  VERSION = meta.core_version
}


local function escape_fwcc_header_element_value(value)
  if ngx_re_match(value, [=[["]]=]) then
    value = value:gsub([["]], [[\"]])
  end

  if ngx_re_match(value, [=[[=,;]]=]) then
    value = fmt([["%s"]], value)
  end

  return value
end


-- envoy implementation of the XFCC header:
-- https://github.com/envoyproxy/envoy/blob/8809f6bfe62e35c5bc42a1c6739167b71c64f637/source/common/http/conn_manager_utility.cc#L411-L504
-- https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_conn_man/headers.html#x-forwarded-client-cert
function TLSMetadataHandler:access(conf)

  if not conf.inject_client_cert_details then
    return
  end

  local ssl_client_escaped_cert = ngx.var.ssl_client_escaped_cert
  if ssl_client_escaped_cert then
    -- add http headers
    set_header(conf.client_cert_header_name, ssl_client_escaped_cert)

    set_header(conf.client_serial_header_name,
      ngx_var.ssl_client_serial)

    set_header(conf.client_cert_issuer_dn_header_name,
      ngx_var.ssl_client_i_dn)

    set_header(conf.client_cert_subject_dn_header_name,
    ngx_var.ssl_client_s_dn)

    set_header(conf.client_cert_fingerprint_header_name,
      ngx_var.ssl_client_fingerprint)

  else
    -- if the connection is not mutual TLS, remove the XFCC header
    clear_header(conf.forwarded_client_cert_header_name)
    kong.log.err("plugin enabled to inject tls client certificate headers, but " ..
      "no client certificate was provided")
    return
  end

  -- TODO: `By` needs the current proxy's cert.
  --       Should call `SSL_get_certificate` in `lua-kong-nginx-modulel` or `lua-resty-openssl` first
  local fwcc_header_value = fmt("Cert=%s;Subject=%s",
                                escape_fwcc_header_element_value(ssl_client_escaped_cert),
                                escape_fwcc_header_element_value(ngx_var.ssl_client_s_dn))

  local x509, err = openssl_x509.new(ngx_var.ssl_client_raw_cert, "PEM")
  if x509 then
    local cert_hash = to_hex(x509:digest("sha256"))
    fwcc_header_value = fmt("%s;Hash=%s", fwcc_header_value, cert_hash)

  else
    kong.log.err("could not create a new x509 instance: ", err)
  end

  local full_chain = resty_kong_tls.get_full_client_certificate_chain()
  if full_chain then
    fwcc_header_value = fmt("%s;Chain=%s", fwcc_header_value,
                            escape_fwcc_header_element_value(escape_uri(full_chain)))
  else
    kong.log.err("could not get full client certificate chain")
  end

  local orig_fwcc_header_value = ngx.req.get_headers()[conf.forwarded_client_cert_header_name]
  if orig_fwcc_header_value then
    if type(orig_fwcc_header_value) == "string" then
      fwcc_header_value = fmt("%s,%s", orig_fwcc_header_value, fwcc_header_value)
    end
  end

  set_header(conf.forwarded_client_cert_header_name, fwcc_header_value)

end

return TLSMetadataHandler
