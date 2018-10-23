local ssl        = require "ngx.ssl"
local singletons = require "kong.singletons"


local ngx_log = ngx.log
local ERR     = ngx.ERR
local DEBUG   = ngx.DEBUG


local function log(lvl, ...)
  ngx_log(lvl, "[ssl] ", ...)
end


local _M = {}


local function find_certificate(sni_name)
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

  return {
    cert = certificate.cert,
    key  = certificate.key,
  }
end


local function parse_pem(pem)
  -- no certificate found
  if not pem then
    return true
  end

  local cert, err = ssl.parse_pem_cert(pem.cert)
  if not cert then
    return nil, "could not parse PEM certificate: " .. err
  end

  local key, err = ssl.parse_pem_priv_key(pem.key)
  if not key then
    return nil, "could not parse PEM private key: " .. err
  end

  pem.parsed_cert = cert
  pem.parsed_key = key

  return pem
end


function _M.execute()
  -- retrieve sni or raw server IP

  local sn, err = ssl.server_name()
  if err then
    log(ERR, "could not retrieve SNI: ", err)
    return ngx.exit(ngx.ERROR)
  end

  if not sn then
    log(DEBUG, "no SNI provided by client, serving ",
               "default proxy SSL certificate")
    -- use fallback certificate
    return
  end

  local pem_cache_key = "pem_ssl_certificates:" .. sn

  local pem, err = singletons.cache:get(pem_cache_key,
                                        { l1_serializer = parse_pem },
                                        find_certificate, sn)
  if err then
    log(ERR, err)
    return ngx.exit(ngx.ERROR)
  end

  if pem == true then
    -- use fallback certificate
    return
  end

  -- set the certificate for this connection

  local ok, err = ssl.clear_certs()
  if not ok then
    log(ERR, "could not clear existing (default) certificates: ", err)
    return ngx.exit(ngx.ERROR)
  end

  ok, err = ssl.set_cert(pem.parsed_cert)
  if not ok then
    log(ERR, "could not set configured certificate: ", err)
    return ngx.exit(ngx.ERROR)
  end

  ok, err = ssl.set_priv_key(pem.parsed_key)
  if not ok then
    log(ERR, "could not set configured private key: ", err)
    return ngx.exit(ngx.ERROR)
  end
end


return _M
