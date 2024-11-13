local ngx_ssl = require "ngx.ssl"
local pl_utils = require "pl.utils"
local mlcache = require "kong.resty.mlcache"
local new_tab = require "table.new"
local constants = require "kong.constants"
local plugin_servers = require "kong.runloop.plugin_servers"
local openssl_x509_store = require "resty.openssl.x509.store"
local openssl_x509 = require "resty.openssl.x509"


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
local tb_insert   = table.insert
local kong = kong
local type = type
local error = error
local assert = assert
local tostring = tostring
local ipairs = ipairs
local ngx_md5 = ngx.md5
local ngx_exit = ngx.exit
local ngx_ERROR = ngx.ERROR


local default_cert_and_key

local DEFAULT_SNI = "*"

local CA_KEY = {
  id = "",
}


local function log(lvl, ...)
  ngx_log(lvl, "[ssl] ", ...)
end


local function parse_cert(cert, parsed)
  if cert == nil then
    return nil, nil, parsed
  end

  if type(cert) == "cdata" then
    return cert, nil, parsed
  end

  local err
  cert, err = parse_pem_cert(cert)
  if not cert then
    return nil, "could not parse PEM certificate: " .. err
  end
  return cert, nil, true
end



local function parse_key(key, parsed)
  if key == nil then
    return nil, nil, parsed
  end

  if type(key) == "cdata" then
    return key, nil, parsed
  end

  local err
  key, err = parse_pem_priv_key(key)
  if not key then
    return nil, "could not parse PEM private key: " .. err
  end
  return key, nil, true
end


local function parse_key_and_cert(row)
  if row == false then
    return default_cert_and_key
  end

  -- parse cert and priv key for later usage by ngx.ssl

  local err, parsed
  local key, key_alt
  local cert, cert_alt

  cert, err, parsed = parse_cert(row.cert)
  if err then
    return nil, err
  end

  key, err, parsed = parse_key(row.key, parsed)
  if err then
    return nil, err
  end

  cert_alt, err, parsed = parse_cert(row.cert_alt, parsed)
  if err then
    return nil, err
  end

  if cert_alt then
    key_alt, err, parsed = parse_key(row.key_alt, parsed)
    if err then
      return nil, err
    end
  end

  if parsed then
    return {
      cert = cert,
      key = key,
      cert_alt = cert_alt,
      key_alt = key_alt,
      ["$refs"] = row["$refs"],
    }
  end

  return row
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
  local row, err = kong.db.snis:select_by_name(sni)
  if err then
    return nil, "failed to fetch '" .. sni .. "' SNI: " .. err, i
  end

  if not row then
    return false, nil, i
  end

  return row, nil, i
end


local function fetch_certificate(pk, sni_name)
  local certificate, err = kong.db.certificates:select(pk)
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
  local conf = kong.configuration
  if conf.ssl_cert[1] then
    default_cert_and_key = parse_key_and_cert {
      cert = assert(pl_utils.readfile(conf.ssl_cert[1])),
      key = assert(pl_utils.readfile(conf.ssl_cert_key[1])),
    }
  end
end


local function get_certificate(pk, sni_name)
  local cache_key = kong.db.certificates:cache_key(pk)
  local certificate, err, hit_level = kong.core_cache:get(cache_key,
                                                          get_certificate_opts,
                                                          fetch_certificate,
                                                          pk, sni_name)

  if certificate and hit_level ~= 3 and certificate["$refs"] then
    certificate = parse_key_and_cert(kong.vault.update(certificate))
  end

  return certificate, err
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

  for _, new_sni, err in mlcache.each_bulk_res(res) do
    if new_sni then
      return get_certificate(new_sni.certificate, new_sni.name)
    end
    if err then
      -- we choose to not call typedefs.wildcard_host.custom_validator(sni)
      -- in the front to reduce the cost in normal flow.
      -- these error messages are from validate_wildcard_host()
      local patterns = {
        "must not be an IP",
        "must not have a port",
        "invalid value: ",
        "only one wildcard must be specified",
        "wildcard must be leftmost or rightmost character",
      }
      local idx

      for _, pat in ipairs(patterns) do
        idx = err:find(pat, nil, true)
        if idx then
          break
        end
      end

      if idx then
        kong.log.debug("invalid SNI '", sni, "', ", err:sub(idx),
                       ", serving default SSL certificate")
      else
        log(ERR, "failed to fetch SNI: ", err)
      end
    end
  end

  return default_cert_and_key
end


local function execute()
  local sn, err = server_name()
  if err then
    log(ERR, "could not retrieve SNI: ", err)
    return ngx_exit(ngx_ERROR)
  end

  local cert_and_key, err = find_certificate(sn)
  if err then
    log(ERR, err)
    return ngx_exit(ngx_ERROR)
  end

  if cert_and_key == default_cert_and_key then
    -- use (already set) fallback certificate
    return
  end

  -- set the certificate for this connection

  local ok, err = clear_certs()
  if not ok then
    log(ERR, "could not clear existing (default) certificates: ", err)
    return ngx_exit(ngx_ERROR)
  end

  ok, err = set_cert(cert_and_key.cert)
  if not ok then
    log(ERR, "could not set configured certificate: ", err)
    return ngx_exit(ngx_ERROR)
  end

  ok, err = set_priv_key(cert_and_key.key)
  if not ok then
    log(ERR, "could not set configured private key: ", err)
    return ngx_exit(ngx_ERROR)
  end

  if cert_and_key.cert_alt and cert_and_key.key_alt then
    ok, err = set_cert(cert_and_key.cert_alt)
    if not ok then
      log(ERR, "could not set alternate configured certificate: ", err)
      return ngx_exit(ngx_ERROR)
    end

    ok, err = set_priv_key(cert_and_key.key_alt)
    if not ok then
      log(ERR, "could not set alternate configured private key: ", err)
      return ngx_exit(ngx_ERROR)
    end
  end
end


local function ca_ids_cache_key(ca_ids)
  tb_sort(ca_ids)
  return "ca_stores:" .. ngx_md5(tb_concat(ca_ids, ':'))
end


local function fetch_ca_certificates(ca_ids)
  local cas = new_tab(#ca_ids, 0)

  for i, ca_id in ipairs(ca_ids) do
    CA_KEY.id = ca_id

    local obj, err = kong.db.ca_certificates:select(CA_KEY)
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


local function get_ca_certificate_store_for_plugin(ca_ids)
  return kong.cache:get(ca_ids_cache_key(ca_ids),
                        get_ca_store_opts, fetch_ca_certificates,
                        ca_ids)
end


-- here we assume the field name is always `ca_certificates`
local get_ca_certificate_reference_entities
do
  local function is_entity_referencing_ca_certificates(name)
    local entity_schema = require("kong.db.schema.entities." .. name)
    for _, field in ipairs(entity_schema.fields) do
      if field.ca_certificates then
        return true
      end
    end

    return false
  end

  -- ordinary entities that reference ca certificates
  -- For example: services
  local CA_CERT_REFERENCE_ENTITIES
  get_ca_certificate_reference_entities = function()
    if not CA_CERT_REFERENCE_ENTITIES then
      CA_CERT_REFERENCE_ENTITIES = {}
      for _, entity_name in ipairs(constants.CORE_ENTITIES) do
        local res = is_entity_referencing_ca_certificates(entity_name)
        if res then
          tb_insert(CA_CERT_REFERENCE_ENTITIES, entity_name)
        end
      end
    end

    return CA_CERT_REFERENCE_ENTITIES
  end
end


-- here we assume the field name is always `ca_certificates`
local get_ca_certificate_reference_plugins
do
  local load_module_if_exists = require "kong.tools.module".load_module_if_exists

  local function is_plugin_referencing_ca_certificates(name)
    local plugin_schema = "kong.plugins." .. name .. ".schema"
    local ok, schema = load_module_if_exists(plugin_schema)
    if not ok then
      ok, schema = plugin_servers.load_schema(name)
    end

    if not ok then
      return nil, "no configuration schema found for plugin: " .. name
    end

    for _, field in ipairs(schema.fields) do
      if field.config then
        for _, field in ipairs(field.config.fields) do
          if field.ca_certificates then
            return true
          end
        end
      end
    end

    return false
  end

  -- loaded plugins that reference ca certificates
  -- For example: mtls-auth
  local CA_CERT_REFERENCE_PLUGINS
  get_ca_certificate_reference_plugins = function()
    if not CA_CERT_REFERENCE_PLUGINS then
      CA_CERT_REFERENCE_PLUGINS = {}
      local loaded_plugins = kong.configuration.loaded_plugins
      for name, v in pairs(loaded_plugins) do
        local res, err = is_plugin_referencing_ca_certificates(name)
        if err then
          return nil, err
        end

        if res then
          CA_CERT_REFERENCE_PLUGINS[name] = true
        end
      end
    end

    return CA_CERT_REFERENCE_PLUGINS
  end
end


return {
  init = init,
  find_certificate = find_certificate,
  produce_wild_snis = produce_wild_snis,
  execute = execute,
  get_certificate = get_certificate,
  get_ca_certificate_store = get_ca_certificate_store,
  get_ca_certificate_store_for_plugin = get_ca_certificate_store_for_plugin,
  ca_ids_cache_key = ca_ids_cache_key,
  get_ca_certificate_reference_entities = get_ca_certificate_reference_entities,
  get_ca_certificate_reference_plugins = get_ca_certificate_reference_plugins,
}
