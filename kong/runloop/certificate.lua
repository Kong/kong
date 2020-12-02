local singletons = require "kong.singletons"
local ngx_ssl = require "ngx.ssl"
local pl_utils = require "pl.utils"
local mlcache = require "resty.mlcache"
local new_tab = require "table.new"
local openssl_x509_store = require "resty.openssl.x509.store"
local openssl_x509 = require "resty.openssl.x509"

if jit.arch == 'arm64' then
  jit.off(mlcache.get_bulk)        -- "temporary" workaround for issue #5748 on ARM
end



local ngx_log     = ngx.log
local ERR         = ngx.ERR
local DEBUG       = ngx.DEBUG
local re_sub      = ngx.re.sub
local find        = string.find
local server_name = ngx_ssl.server_name
local clear_certs = ngx_ssl.clear_certs
local parse_pem_cert = ngx_ssl.parse_pem_cert
local parse_pem_priv_key = ngx_ssl.parse_pem_priv_key
local set_cert = ngx_ssl.set_cert
local set_priv_key = ngx_ssl.set_priv_key
local tb_concat   = table.concat
local tb_sort   = table.sort
local tostring = tostring
local ipairs = ipairs
local ngx_md5 = ngx.md5


local default_cert_and_key

local DEFAULT_SNI = "*"

local function log(lvl, ...)
  ngx_log(lvl, "[ssl] ", ...)
end

local function parse_key_and_cert(row)
  if row == false then
    return default_cert_and_key
  end

  -- parse cert and priv key for later usage by ngx.ssl

  local cert, err = parse_pem_cert(row.cert)
  if not cert then
    return nil, "could not parse PEM certificate: " .. err
  end

  local key, err = parse_pem_priv_key(row.key)
  if not key then
    return nil, "could not parse PEM private key: " .. err
  end

  local cert_alt
  local key_alt
  if row.cert_alt and row.key_alt then
    cert_alt, err = parse_pem_cert(row.cert_alt)
    if not cert_alt then
      return nil, "could not parse alternate PEM certificate: " .. err
    end

    key_alt, err = parse_pem_priv_key(row.key_alt)
    if not key_alt then
      return nil, "could not parse alternate PEM private key: " .. err
    end
  end

  return {
    cert = cert,
    key = key,
    cert_alt = cert_alt,
    key_alt = key_alt,
  }
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


local function fetch_certificate(pk, sni_name)
  local certificate, err = singletons.db.certificates:select(pk)
  if err then
    if sni_name then
      return nil, "failed to fetch certificate for '" .. sni_name .. "' SNI: " ..
                  err
    end

    return nil, "failed to fetch certificate " .. pk.id
  end

  if not certificate then
    if sni_name then
      return nil, "no SSL certificate configured for sni: " .. sni_name
    end

    return nil, "certificate " .. pk.id .. " not found"
  end

  return certificate
end


local get_certificate_opts = {
  l1_serializer = parse_key_and_cert,
}


local get_ca_store_opts = {
  l1_serializer = function(cas)
    local trust_store, err = openssl_x509_store.new()
    if err then
      return nil, err
    end

    for _, ca in ipairs(cas) do
      local x509, err = openssl_x509.new(ca.cert, "PEM")
      if err then
        return nil, err
      end

      local _, err = trust_store:add(x509)
      if err then
        return nil, err
      end
    end

    return trust_store
  end,
}


local function init()
  if singletons.configuration.ssl_cert[1] then
    default_cert_and_key = parse_key_and_cert {
      cert = assert(pl_utils.readfile(singletons.configuration.ssl_cert[1])),
      key = assert(pl_utils.readfile(singletons.configuration.ssl_cert_key[1])),
    }
  end
end


local function get_certificate(pk, sni_name)
  return kong.core_cache:get("certificates:" .. pk.id,
                        get_certificate_opts, fetch_certificate,
                        pk, sni_name)
end


local function find_certificate(sni)
  if not sni then
    log(DEBUG, "no SNI provided by client, serving default SSL certificate")
    return default_cert_and_key
  end

  local sni_wild_pref, sni_wild_suf = produce_wild_snis(sni)

  local bulk = mlcache.new_bulk(4)

  bulk:add("snis:" .. sni, nil, fetch_sni, sni)

  if sni_wild_pref then
    bulk:add("snis:" .. sni_wild_pref, nil, fetch_sni, sni_wild_pref)
  end

  if sni_wild_suf then
    bulk:add("snis:" .. sni_wild_suf, nil, fetch_sni, sni_wild_suf)
  end

  bulk:add("snis:" .. DEFAULT_SNI, nil, fetch_sni, DEFAULT_SNI)

  local res, err = kong.core_cache:get_bulk(bulk)
  if err then
    return nil, err
  end

  for _, sni, err in mlcache.each_bulk_res(res) do
    if err then
      log(ERR, "failed to fetch SNI: ", err)

    elseif sni then
      return get_certificate(sni.certificate, sni.name)
    end
  end

  return default_cert_and_key
end


local function execute()
  local sn, err = server_name()
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

  local ok, err = clear_certs()
  if not ok then
    log(ERR, "could not clear existing (default) certificates: ", err)
    return ngx.exit(ngx.ERROR)
  end

  ok, err = set_cert(cert_and_key.cert)
  if not ok then
    log(ERR, "could not set configured certificate: ", err)
    return ngx.exit(ngx.ERROR)
  end

  ok, err = set_priv_key(cert_and_key.key)
  if not ok then
    log(ERR, "could not set configured private key: ", err)
    return ngx.exit(ngx.ERROR)
  end

  if cert_and_key.cert_alt and cert_and_key.key_alt then
    ok, err = set_cert(cert_and_key.cert_alt)
    if not ok then
      log(ERR, "could not set alternate configured certificate: ", err)
      return ngx.exit(ngx.ERROR)
    end

    ok, err = set_priv_key(cert_and_key.key_alt)
    if not ok then
      log(ERR, "could not set alternate configured private key: ", err)
      return ngx.exit(ngx.ERROR)
    end
  end
end


local function ca_ids_cache_key(ca_ids)
  tb_sort(ca_ids)
  return "ca_stores:" .. ngx_md5(tb_concat(ca_ids, ':'))
end


local function fetch_ca_certificates(ca_ids)
  local cas = new_tab(#ca_ids, 0)
  local key = new_tab(1, 0)

  for i, ca_id in ipairs(ca_ids) do
    key.id = ca_id

    local obj, err = kong.db.ca_certificates:select(key)
    if not obj then
      if err then
        return nil, err
      end

      return nil, "CA Certificate '" .. tostring(ca_id) .. "' does not exist"
    end

    cas[i] = obj
  end

  return cas
end


local function get_ca_certificate_store(ca_ids)
  return kong.core_cache:get(ca_ids_cache_key(ca_ids),
                         get_ca_store_opts, fetch_ca_certificates,
                         ca_ids)
end


return {
  init = init,
  find_certificate = find_certificate,
  produce_wild_snis = produce_wild_snis,
  execute = execute,
  get_certificate = get_certificate,
  get_ca_certificate_store = get_ca_certificate_store,
}
