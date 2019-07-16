local singletons = require "kong.singletons"
local ngx_ssl = require "ngx.ssl"
local http_tls = require "http.tls"
local openssl_pkey = require "openssl.pkey"
local openssl_x509 = require "openssl.x509"
local pl_utils = require "pl.utils"
local mlcache = require "resty.mlcache"


local ngx_log = ngx.log
local ERR     = ngx.ERR
local DEBUG   = ngx.DEBUG
local re_sub  = ngx.re.sub
local find    = string.find


local default_cert_and_key
local parse_key_and_cert


local function log(lvl, ...)
  ngx_log(lvl, "[ssl] ", ...)
end


if ngx.config.subsystem == "http" then
  parse_key_and_cert = function(row)
    if row == false then
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

else
  parse_key_and_cert = function(row)
    if row == false then
      return default_cert_and_key
    end

    local ssl_termination_ctx = http_tls.new_server_context()
    ssl_termination_ctx:setCertificate(openssl_x509.new(row.cert))
    ssl_termination_ctx:setPrivateKey(openssl_pkey.new(row.key))

    return ssl_termination_ctx
  end
end


local function produce_wild_snis(sni)
  if type(sni) ~= "string" then
    error("sni must be a string", 2)
  end

  local wild_prefix_sni
  local wild_suffix_sni

  local wild_idx = find(sni, "*", nil, true)

  if wild_idx == 1 then
    wild_prefix_sni = sni

  elseif not wild_idx then
    -- *.example.com lookup
    local wild_sni, n, err = re_sub(sni, [[([^.]+)(\.[^.]+\.\S+)]], "*$2",
                                    "ajo")
    if err then
      log(ERR, "could not create SNI wildcard for SNI lookup: ", err)

    elseif n > 0 then
      wild_prefix_sni = wild_sni
    end
  end

  if wild_idx == #sni then
    wild_suffix_sni = sni

  elseif not wild_idx then
    -- example.* lookup
    local wild_sni, n, err = re_sub(sni, [[([^.]+\.)([^.]+)$]], "$1*", "jo")
    if err then
      log(ERR, "could not create SNI wildcard for SNI lookup: ", err)

    elseif n > 0 then
      wild_suffix_sni = wild_sni
    end
  end

  return wild_prefix_sni, wild_suffix_sni
end


local function fetch_sni(sni, i)
  local row, err = singletons.db.snis:select_by_name(sni)
  if err then
    return nil, "failed to fetch '" .. sni .. "' SNI: " .. err, i
  end

  if not row then
    return false, nil, i
  end

  return row, nil, i
end


local function fetch_certificate(pkey, sni_name)
  local certificate, err = singletons.db.certificates:select(pkey)
  if err then
    if sni_name then
      return nil, "failed to fetch certificate for '" .. sni_name .. "' SNI: " ..
                  err
    end

    return "failed to fetch certificate " .. pkey.id
  end

  if not certificate then
    if sni_name then
      return nil, "no SSL certificate configured for sni: " .. sni_name
    end

    return nil, "certificate " .. pkey.id .. " not found"
  end

  return certificate
end


local get_certificate_opts = {
  l1_serializer = parse_key_and_cert,
}


local function init()
  default_cert_and_key = parse_key_and_cert {
    cert = assert(pl_utils.readfile(singletons.configuration.ssl_cert)),
    key = assert(pl_utils.readfile(singletons.configuration.ssl_cert_key)),
  }
end


local function get_certificate(pkey, sni_name)
  return kong.cache:get("certificates:" .. pkey.id,
                        get_certificate_opts, fetch_certificate,
                        pkey, sni_name)
end


local function find_certificate(sni)
  if not sni then
    log(DEBUG, "no SNI provided by client, serving default SSL certificate")
    return default_cert_and_key
  end

  local sni_wild_pref, sni_wild_suf = produce_wild_snis(sni)

  local bulk = mlcache.new_bulk(3)

  bulk:add("snis:" .. sni, nil, fetch_sni, sni)

  if sni_wild_pref then
    bulk:add("snis:" .. sni_wild_pref, nil, fetch_sni, sni_wild_pref)
  end

  if sni_wild_suf then
    bulk:add("snis:" .. sni_wild_suf, nil, fetch_sni, sni_wild_suf)
  end

  local res, err = kong.cache:get_bulk(bulk)
  if err then
    return nil, err
  end

  for i, sni, err in mlcache.each_bulk_res(res) do
    if err then
      log(ERR, "failed to fetch SNI: ", err)

    elseif sni then
      return get_certificate(sni.certificate, sni.name)
    end
  end

  return default_cert_and_key
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
  produce_wild_snis = produce_wild_snis,
  execute = execute,
  get_certificate = get_certificate,
}
