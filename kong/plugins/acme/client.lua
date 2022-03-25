local acme = require "resty.acme.client"
local util = require "resty.acme.util"
local x509 = require "resty.openssl.x509"

local cjson = require "cjson"
local ngx_ssl = require "ngx.ssl"

local dbless = kong.configuration.database == "off"
local hybrid_mode = kong.configuration.role == "control_plane" or
                    kong.configuration.role == "data_plane"

local RENEW_KEY_PREFIX = "kong_acme:renew_config:"
local RENEW_LAST_RUN_KEY = "kong_acme:renew_last_run"
local CERTKEY_KEY_PREFIX = "kong_acme:cert_key:"

local LOCK_TIMEOUT = 30 -- in seconds
local CACHE_TTL = 3600 -- in seconds
local CACHE_NEG_TTL = 5

local function account_name(conf)
  return "kong_acme:account:" .. conf.api_uri .. ":" ..
                      ngx.encode_base64(conf.account_email)
end

local function deserialize_account(j)
  j = cjson.decode(j)
  if not j.key then
    return nil, "key found in account"
  end
  return j
end

local function deserialize_certkey(j)
  local certkey = cjson.decode(j)
  if not certkey.key or not certkey.key then
    return nil, "key or cert found in storage"
  end

  local cert, err = ngx_ssl.cert_pem_to_der(certkey.cert)
  if err then
    return nil, err
  end
  local key, err = ngx_ssl.priv_key_pem_to_der(certkey.key)
  if err then
    return nil, err
  end
  return {
    key = key,
    cert = cert,
  }
end

local function cached_get(storage, key, deserializer, ttl, neg_ttl)
  local cache_key = kong.db.acme_storage:cache_key(key)
  return kong.cache:get(cache_key, {
    l1_serializer = deserializer,
    -- in dbless mode, kong.cache has mlcache set to 0 as ttl
    -- we override the default setting here so that cert can be invalidated
    -- with renewal.
    ttl = math.max(ttl or CACHE_TTL, 0),
    neg_ttl = math.max(neg_ttl or CACHE_NEG_TTL, 0),
  }, storage.get, storage, key)
end

local function new_storage_adapter(conf)
  local storage = conf.storage
  if not storage then
    return nil, nil, "storage is nil"
  end
  local storage_config = conf.storage_config[storage]
  if not storage_config then
    return nil, nil, storage .. " is not defined in plugin storage config"
  end
  if storage == "kong" then
    storage = "kong.plugins.acme.storage.kong"
  else
    storage = "resty.acme.storage." .. storage
  end
  local lib = require(storage)
  local st, err = lib.new(storage_config)
  return storage, st, err
end

local function new(conf)
  local storage_full_path, st, err = new_storage_adapter(conf)
  if err then
    return nil, err
  end
  local account_name = account_name(conf)
  local account, err = cached_get(st, account_name, deserialize_account)
  if err then
    return nil, err
  elseif not account then
    -- TODO: populate new account?
    return nil, "account ".. conf.account_email .. " not found in storage"
  end

  -- backward compat
  local url = conf.api_uri
  if not ngx.re.match(url, "/directory$") then
    if not ngx.re.match(url, "/$") then
      url = url .. "/"
    end
    url = url .. "directory"
  end

  -- TODO: let acme accept initlizaed storage table alternatively
  return acme.new({
    account_email = conf.account_email,
    account_key = account.key,
    api_uri = url,
    storage_adapter = storage_full_path,
    storage_config = conf.storage_config[conf.storage],
    eab_kid = conf.eab_kid,
    eab_hmac_key = conf.eab_hmac_key,
    challenge_start_callback = hybrid_mode and function()
      -- The delayed-push mechanism in hybrid mode may result in up to
      -- 2 times of db_update_frequency (the time push delayed) duration
      local wait = kong.configuration.db_update_frequency * 2
      kong.log.info("Kong is running in Hybrid mode, wait for ", wait,
                    " seconds for ACME challenges to propogate")
      ngx.sleep(wait)
      return true
    end or nil,
    preferred_chain = conf.preferred_chain,
  })
end

local function order(acme_client, host, key, cert_type, rsa_key_size)
  local err = acme_client:init()
  if err then
    return nil, nil, err
  end

  local _, err = acme_client:new_account()
  if err then
    return nil, nil, err
  end

  if not key then
    -- FIXME: this might block worker for several seconds in some virtualization env
    if cert_type == "rsa" then
      key = util.create_pkey(rsa_key_size, 'RSA')
    else
      key = util.create_pkey(nil, 'EC', 'prime256v1')
    end
  end

  local cert, err = acme_client:order_certificate(key, host)
  if err then
    return nil, nil, "could not create certificate: " .. err
  end

  return cert, key, nil
end

-- idempotent routine for updating sni and certificate in Kong database
local function save_dao(host, key, cert)
  local cert_entity, err = kong.db.certificates:insert({
    cert = cert,
    key = key,
    tags = { "managed-by-acme" },
  })

  if err then
    return "could not insert cert: " .. err
  end

  local old_sni_entity, err = kong.db.snis:select_by_name(host)
  if err then
    kong.log.warn("error finding sni entity: ", err)
  end

  local _, err = kong.db.snis:upsert_by_name(host, {
    certificate = cert_entity,
    tags = { "managed-by-acme" },
  })

  if err then
    local ok, err_2 = kong.db.certificates:delete({
      id = cert_entity.id,
    })
    if not ok then
      kong.log.warn("error cleaning up certificate entity ", cert_entity.id, ": ", err_2)
    end
    return "could not upsert sni: " .. err
  end

  if old_sni_entity and old_sni_entity.certificate then
    local id = old_sni_entity.certificate.id
    local ok, err = kong.db.certificates:delete({
      id = id,
    })
    if not ok then
      kong.log.warn("error deleting expired certificate entity ", id, ": ", err)
    end
  end
end

local function store_renew_config(conf, host)
  local _, st, err = new_storage_adapter(conf)
  if err then
    return err
  end
  -- Note: we don't distinguish api uri because host is unique in Kong SNIs
  err = st:set(RENEW_KEY_PREFIX .. host, cjson.encode({
    host = host,
    expire_at = ngx.time() + 86400 * 90,
  }))
  return err
end

local function create_account(conf)
  local _, st, err = new_storage_adapter(conf)
  if err then
    return err
  end
  local account_name = account_name(conf)
  local account, err = st:get(account_name)
  if err then
    return err
  elseif account then
    return
  end
  -- no account yet, create one now
  local pkey = util.create_pkey(4096, "RSA")

  local err = st:set(account_name, cjson.encode({
    key = pkey,
  }))
  if err then
    return err
  end
  conf.account_key = nil
  return
end

local function update_certificate(conf, host, key)
  local _, st, err = new_storage_adapter(conf)
  if err then
    return false, "can't create storage adapter: " .. err
  end

  local backoff_key = "kong_acme:fail_backoff:" .. host
  local backoff_until, err = st:get(backoff_key)
  if err then
    kong.log.warn("failed to read backoff status for ", host, " : ", err)
  end
  if backoff_until and tonumber(backoff_until) then
    local wait = tonumber(backoff_until) - ngx.time()
    return false, "please try again in " .. wait .. " seconds for host " ..
            host .. " because of previous failure; this is configurable " ..
            "with config.fail_backoff_minutes"
  end

  local lock_key = "kong_acme:update_lock:" .. host
  -- TODO: wait longer?
  -- This goes to the backend storage and may bring pressure, add a first pass shm cache?
  local err = st:add(lock_key, "placeholder", LOCK_TIMEOUT)
  if err then
    kong.log.info("update_certificate for ", host, " is already running: ", err)
    return false
  end
  local acme_client, cert, err
  err = create_account(conf)
  if err then
    goto update_certificate_error
  end
  acme_client, err = new(conf)
  if err then
    goto update_certificate_error
  end
  cert, key, err = order(acme_client, host, key, conf.cert_type, conf.rsa_key_size)
  if not err then
    if dbless or hybrid_mode then
      -- in dbless mode, we don't actively release lock
      -- since we don't implement an IPC to purge potentially negatively
      -- cached cert/key in other node, we set the cache to be same as
      -- lock timeout, so that multiple node will not try to update certificate
      -- at the same time because they are all seeing default cert is served
      local err = st:set(CERTKEY_KEY_PREFIX .. host, cjson.encode({
        key = key,
        cert = cert,
      }))
      return true, err
    else
      err = save_dao(host, key, cert)
    end
  end
::update_certificate_error::
  local wait_seconds = conf.fail_backoff_minutes * 60
  local err_set = st:set(backoff_key, string.format("%d", ngx.time() + wait_seconds), wait_seconds)
  if err_set then
    kong.log.warn("failed to set fallback key for ", host, ": ", err_set)
  end

  local err_del = st:delete(lock_key)
  if err_del then
    kong.log.warn("failed to delete update_certificate lock for ", host, ": ", err_del)
  end
  return true, err
end

local function check_expire(cert, threshold)
  local crt, err = x509.new(cert)
  if err then
    kong.log.info("can't parse cert stored in storage: ", err)
  elseif crt:get_not_after() - threshold > ngx.time() then
    return false
  end

  return true
end

-- loads existing cert and key for host from storage or Kong database
local function load_certkey(conf, host)
  if dbless or hybrid_mode then
    local _, st, err = new_storage_adapter(conf)
    if err then
      return nil, err
    end

    local certkey, err = st:get(CERTKEY_KEY_PREFIX .. host)
    if err then
      return nil, err
    elseif not certkey then
      return nil
    end

    return cjson.decode(certkey)
  end

  local sni_entity, err = kong.db.snis:select_by_name(host)
  if err then
    return nil, "can't read SNI entity"
  elseif not sni_entity then
    kong.log.info("SNI ", host, " is not found in Kong database")
    return
  end

  if not sni_entity or not sni_entity.certificate then
    return nil, "DAO returns empty SNI entity or Certificte entity"
  end

  local cert_entity, err = kong.db.certificates:select({ id = sni_entity.certificate.id })
  if err then
    kong.log.info("can't read certificate ", sni_entity.certificate.id, " from db",
                  ", deleting renew config")
    return nil, nil
  elseif not cert_entity then
    kong.log.warn("certificate for SNI ", host, " is not found in Kong database")
    return nil, nil
  end

  return {
    cert = cert_entity.cert,
    key = cert_entity.key,
  }
end

local function load_certkey_cached(conf, host)
  local _, st, err = new_storage_adapter(conf)
  if err then
    return nil, err
  end
  local key = CERTKEY_KEY_PREFIX .. host
  return cached_get(st, key, deserialize_certkey)
end

local function renew_certificate_storage(conf)
  local _, st, err = new_storage_adapter(conf)
  if err then
    kong.log.err("can't create storage adapter: ", err)
    return
  end

  local renew_conf_keys, err = st:list(RENEW_KEY_PREFIX)
  if err then
    kong.log.err("can't list renew hosts: ", err)
    return
  end
  err = st:set(RENEW_LAST_RUN_KEY, ngx.localtime())
  if err then
    kong.log.warn("can't set renew_last_run: ", err)
  end

  for _, renew_conf_key in ipairs(renew_conf_keys) do
    local renew_conf, err = st:get(renew_conf_key)
    if err then
      kong.log.err("can't read renew conf: ", err)
      goto renew_continue
    end
    if not renew_conf then
      kong.log.err("renew config key ",renew_conf_key, " is empty")
      goto renew_continue
    end

    renew_conf = cjson.decode(renew_conf)

    local host = renew_conf.host
    local expire_threshold = 86400 * conf.renew_threshold_days
    if renew_conf.expire_at - expire_threshold > ngx.time() then
      kong.log.info("certificate for host ", host, " is not due for renewal")
      goto renew_continue
    end

    local certkey, err = load_certkey(conf, host)
    if err then
      kong.log.err("error loading existing certkey for host: ", host, ": ", err)
      goto renew_continue
    end

    if not certkey then
      kong.log.warn("deleting renewal config for host: ", host)
      err = st:delete(renew_conf_key)
      if err then
        kong.log.warn("error deleting unneeded renew config key \"", renew_conf_key, "\"")
      end
      goto renew_continue
    end

    local renew, err = check_expire(certkey.cert, expire_threshold)
    if err then
      kong.log.err("error checking expiry for certificate of host: ", host, ": ", err)
      goto renew_continue
    end

    if not renew then
      kong.log.info("certificate for ", host, " is not due for renewal")
      goto renew_continue
    end

    if not certkey.key then
      kong.log.info("previous key is not defined, creating new key")
    end

    kong.log.info("renew certificate for host ", host)
    local _, err = update_certificate(conf, host, certkey.key)
    if err then
      kong.log.err("failed to renew certificate: ", err)
    end

::renew_continue::
  end

end

local function renew_certificate(premature)
  if premature then
    return
  end

  for plugin, err in kong.db.plugins:each(1000) do
    if err then
      kong.log.warn("error fetching plugin: ", err)
    end

    if plugin.name == "acme" then
      kong.log.info("renew storage configured in acme plugin: ", plugin.id)
      renew_certificate_storage(plugin.config)
    end
  end
end

local function load_renew_hosts(conf)
  local _, st, err = new_storage_adapter(conf)
  if err then
    return nil, err
  end
  local hosts, err = st:list(RENEW_KEY_PREFIX)
  if err then
    return nil, err
  end

  local data = {}
  for i, host in ipairs(hosts) do
    data[i] = string.sub(host, #RENEW_KEY_PREFIX + 1)
  end
  return data
end

return {
  new = new,
  create_account = create_account,
  update_certificate = update_certificate,
  renew_certificate = renew_certificate,
  store_renew_config = store_renew_config,
  load_renew_hosts = load_renew_hosts,
  load_certkey = load_certkey,
  load_certkey_cached = load_certkey_cached,

  -- for test only
  _save_dao = save_dao,
  _order = order,
  _account_name = account_name,
  _renew_key_prefix = RENEW_KEY_PREFIX,
  _certkey_key_prefix = CERTKEY_KEY_PREFIX,
  _renew_certificate_storage = renew_certificate_storage,
  _check_expire = check_expire,
  _set_is_dbless = function(d) dbless = d end,
}
