local ssl = require "ngx.ssl"
local cache = require "kong.tools.database_cache"
--local lrucache = require "resty.lrucache"
local singletons = require "kong.singletons"


local ngx_log = ngx.log
local ERR     = ngx.ERR
--local INFO    = ngx.INFO
local DEBUG   = ngx.DEBUG
--local ssl_certs_cache


local function log(lvl, ...)
  ngx_log(lvl, "[ssl] ", ...)
end


--[[
do
  local err
  ssl_certs_cache, err = lrucache.new(100)
  if not ssl_certs_cache then
    log(ERR, "could not create certs cache: ", err)
  end
end
--]]


local _M = {}


local function find_certificate(sni)
  local row, err = singletons.dao.ssl_servers_names:find {
    name = sni
  }
  if err then
    return nil, err
  end

  if not row then
    log(DEBUG, "no server name registered for client-provided SNI")
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

  -- parse cert and priv key for later usage by ngx.ssl

  local cert, err = ssl.parse_pem_cert(ssl_certificate.cert)
  if not cert then
    return nil, "could not parse PEM certificate: " .. err
  end

  local key, err = ssl.parse_pem_priv_key(ssl_certificate.key)
  if not key then
    return nil, "could not parse PEM private key: " .. err
  end

  -- cached value

  return {
    cert = cert,
    key  = key,
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

  local cert_and_key, err
  --local cert_and_key = ssl_certs_cache:get(sni)
  --if not cert_and_key then
    -- miss
    -- check shm cache
    cert_and_key, err = cache.get_or_set(cache.certificate_key(sni), nil,
                                         find_certificate, sni)
    if not cert_and_key then
      log(ERR, err)
      return ngx.exit(ngx.ERROR)
    end

    -- set Lua-land LRU cache

    --ssl_certs_cache:set(sni, cert_and_key)
  --end

  if cert_and_key == true then
    -- use fallback certificate
    return
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
