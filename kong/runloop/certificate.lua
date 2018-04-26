local ssl        = require "ngx.ssl"
local singletons = require "kong.singletons"


local ngx_log = ngx.log
local ERR     = ngx.ERR
local DEBUG   = ngx.DEBUG


local function log(lvl, ...)
  ngx_log(lvl, "[ssl] ", ...)
end


local _M = {}


local function find_certificate(sni)
  local row, err = singletons.dao.ssl_servers_names:find {
    name = sni
  }
  if err then
    return nil, err
  end

  if not row then
    log(DEBUG, "no server name registered for client-provided SNI: '",
               sni, "'")
    return true
  end

  -- fetch SSL certificate for this SNI

  local ssl_certificate, err = singletons.dao.ssl_certificates:find {
    id = row.ssl_certificate_id
  }
  if err then
    return nil, err
  end

  if not ssl_certificate then
    return nil, "no SSL certificate configured for server name: " .. sni
  end

  return {
    cert = ssl_certificate.cert,
    key  = ssl_certificate.key,
  }
end


function _M.execute()
  -- retrieve SNI or raw server IP

  local sni, err = ssl.server_name()
  if err then
    log(ERR, "could not retrieve Server Name Indication: ", err)
    return ngx.exit(ngx.ERROR)
  end

  if not sni then
    log(DEBUG, "no Server Name Indication provided by client, serving ",
               "default proxy SSL certificate")
    -- use fallback certificate
    return
  end

  local lru              = singletons.cache.mlcache.lru
  local pem_cache_key    = "pem_ssl_certificates:" .. sni
  local parsed_cache_key = "parsed_ssl_certificates:" .. sni

  local pem_cert_and_key, err = singletons.cache:get(pem_cache_key, nil,
                                                     find_certificate, sni)
  if not pem_cert_and_key then
    log(ERR, err)
    return ngx.exit(ngx.ERROR)
  end

  if pem_cert_and_key == true then
    -- use fallback certificate
    return
  end

  local cert_and_key = lru:get(parsed_cache_key)
  if not cert_and_key then
    -- parse cert and priv key for later usage by ngx.ssl

    local cert, err = ssl.parse_pem_cert(pem_cert_and_key.cert)
    if not cert then
      return nil, "could not parse PEM certificate: " .. err
    end

    local key, err = ssl.parse_pem_priv_key(pem_cert_and_key.key)
    if not key then
      return nil, "could not parse PEM private key: " .. err
    end

    cert_and_key = {
      cert = cert,
      key = key,
    }

    lru:set(parsed_cache_key, cert_and_key)
  end

  -- set the certificate for this connection

  local ok, err = ssl.clear_certs()
  if not ok then
    log(ERR, "could not clear existing (default) certificates: ", err)
    return ngx.exit(ngx.ERROR)
  end

  ok, err = ssl.set_cert(cert_and_key.cert)
  if not ok then
    log(ERR, "could not set configured certificate: ", err)
    return ngx.exit(ngx.ERROR)
  end

  ok, err = ssl.set_priv_key(cert_and_key.key)
  if not ok then
    log(ERR, "could not set configured private key: ", err)
    return ngx.exit(ngx.ERROR)
  end
end


return _M
