local singletons = require "kong.singletons"
local ngx_ssl = require "ngx.ssl"
local http_tls = require "http.tls"
local openssl_pkey = require "openssl.pkey"
local openssl_x509 = require "openssl.x509"
local pl_utils = require "pl.utils"


local ngx_log = ngx.log
local ERR     = ngx.ERR
local DEBUG   = ngx.DEBUG


local default_cert_and_key


local function log(lvl, ...)
  ngx_log(lvl, "[ssl] ", ...)
end


local function fetch_certificate(sni_name)
  local row, err = singletons.db.snis:select_by_name(sni_name)
  if err then
    return nil, err
  end

  if not row then
    log(DEBUG, "no SNI registered for client-provided name: '",
               sni_name, "'")
    return true
  end

  -- fetch SSL certificate for this sni

  local certificate, err = singletons.db.certificates:select(row.certificate)
  if err then
    return nil, err
  end

  if not certificate then
    return nil, "no SSL certificate configured for sni: " .. sni_name
  end

  return certificate
end


local function ngx_parse_key_and_cert(row)
  if row == true then
    return default_cert_and_key
  end

  -- parse cert and priv key for later usage by ngx.ssl

  local cert, err = ngx_ssl.parse_pem_cert(row.cert)
  if not cert then
    return nil, "could not parse PEM certificate: " .. err
  end

  local key, err = ngx_ssl.parse_pem_priv_key(row.key)
  if not key then
    return nil, "could not parse PEM private key: " .. err
  end

  return {
    cert = cert,
    key = key,
  }
end


local function luaossl_parse_key_and_cert(row)
  if row == true then
    return default_cert_and_key
  end

  local ssl_termination_ctx = http_tls.new_server_context()
  ssl_termination_ctx:setCertificate(openssl_x509.new(row.cert))
  ssl_termination_ctx:setPrivateKey(openssl_pkey.new(row.key))

  return ssl_termination_ctx
end


local parse_key_and_cert
if ngx.config.subsystem == "http" then
  parse_key_and_cert = ngx_parse_key_and_cert
else
  parse_key_and_cert = luaossl_parse_key_and_cert
end


local function init()
  default_cert_and_key = parse_key_and_cert {
    cert = assert(pl_utils.readfile(singletons.configuration.ssl_cert)),
    key = assert(pl_utils.readfile(singletons.configuration.ssl_cert_key)),
  }
end


local get_opts = {
  l1_serializer = parse_key_and_cert,
}
local function find_certificate(sn)
  if not sn then
    log(DEBUG, "no SNI provided by client, serving default SSL certificate")
    return default_cert_and_key
  end

  local cache_key = "certificates:" .. sn

  return singletons.cache:get(cache_key, get_opts, fetch_certificate, sn)
end


local function execute()
  local sn, err = ngx_ssl.server_name()
  if err then
    log(ERR, "could not retrieve SNI: ", err)
    return ngx.exit(ngx.ERROR)
  end

  local cert_and_key, err = find_certificate(sn)
  if err then
    log(ERR, err)
    return ngx.exit(ngx.ERROR)
  end

  if cert_and_key == default_cert_and_key then
    -- use (already set) fallback certificate
    return
  end

  -- set the certificate for this connection

  local ok, err = ngx_ssl.clear_certs()
  if not ok then
    log(ERR, "could not clear existing (default) certificates: ", err)
    return ngx.exit(ngx.ERROR)
  end

  ok, err = ngx_ssl.set_cert(cert_and_key.cert)
  if not ok then
    log(ERR, "could not set configured certificate: ", err)
    return ngx.exit(ngx.ERROR)
  end

  ok, err = ngx_ssl.set_priv_key(cert_and_key.key)
  if not ok then
    log(ERR, "could not set configured private key: ", err)
    return ngx.exit(ngx.ERROR)
  end
end


return {
  init = init,
  find_certificate = find_certificate,
  execute = execute,
}
