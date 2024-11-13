local certificate  = require "kong.runloop.certificate"
local ktls         = require "resty.kong.tls"


local kong         = kong
local ngx          = ngx
local log          = ngx.log
local ERR          = ngx.ERR
local CRIT         = ngx.CRIT

local get_certificate                = certificate.get_certificate
local get_ca_certificate_store       = certificate.get_ca_certificate_store
local set_upstream_cert_and_key      = ktls.set_upstream_cert_and_key
local set_upstream_ssl_verify        = ktls.set_upstream_ssl_verify
local set_upstream_ssl_verify_depth  = ktls.set_upstream_ssl_verify_depth
local set_upstream_ssl_trusted_store = ktls.set_upstream_ssl_trusted_store


local function set_service_ssl(ctx)
  local service = ctx and ctx.service

  if not service then
    return
  end

  local res, err
  local client_certificate = service.client_certificate

  if client_certificate then
    local cert, err = get_certificate(client_certificate)
    if not cert then
      log(ERR, "unable to fetch upstream client TLS certificate ",
               client_certificate.id, ": ", err)
      return
    end

    res, err = set_upstream_cert_and_key(cert.cert, cert.key)
    if not res then
      log(ERR, "unable to apply upstream client TLS certificate ",
               client_certificate.id, ": ", err)
    end
  end

  local tls_verify = service.tls_verify
  if tls_verify ~= nil then
    res, err = set_upstream_ssl_verify(tls_verify)
    if not res then
      log(CRIT, "unable to set upstream TLS verification to: ",
                tls_verify, ", err: ", err)
    end
  end

  local tls_verify_depth = service.tls_verify_depth
  if tls_verify_depth then
    res, err = set_upstream_ssl_verify_depth(tls_verify_depth)
    if not res then
      log(CRIT, "unable to set upstream TLS verification to: ",
                tls_verify, ", err: ", err)
      -- in case verify can not be enabled, request can no longer be
      -- processed without potentially compromising security
      return kong.response.exit(500)
    end
  end

  local ca_certificates = service.ca_certificates
  if ca_certificates then
    res, err = get_ca_certificate_store(ca_certificates)
    if not res then
      log(CRIT, "unable to get upstream TLS CA store, err: ", err)

    else
      res, err = set_upstream_ssl_trusted_store(res)
      if not res then
        log(CRIT, "unable to set upstream TLS CA store, err: ", err)
      end
    end
  end
end

local function fallback_upstream_client_cert(ctx, upstream)
  if not ctx then
    return
  end

  upstream = upstream or (ctx.balancer_data and ctx.balancer_data.upstream)

  if not upstream then
    return
  end

  if ctx.service and ctx.service.client_certificate then
    return
  end

  -- service level client_certificate is not set
  local cert, res, err
  local client_certificate = upstream.client_certificate

  -- does the upstream object contains a client certificate?
  if not client_certificate then
    return
  end

  cert, err = get_certificate(client_certificate)
  if not cert then
    log(ERR, "unable to fetch upstream client TLS certificate ",
             client_certificate.id, ": ", err)
    return
  end

  res, err = set_upstream_cert_and_key(cert.cert, cert.key)
  if not res then
    log(ERR, "unable to apply upstream client TLS certificate ",
             client_certificate.id, ": ", err)
  end
end

return {
  set_service_ssl = set_service_ssl,
  fallback_upstream_client_cert = fallback_upstream_client_cert,
}
