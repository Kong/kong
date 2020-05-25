local acme = require "resty.acme.client"
local util = require "resty.acme.util"
local x509 = require "resty.openssl.x509"

local cjson = require "cjson"
local ngx_ssl = require "ngx.ssl"

local dbless = kong.configuration.database == "off"

local RENEW_KEY_PREFIX = "kong_acme:renew_config:"
local RENEW_LAST_RUN_KEY = "kong_acme:renew_last_run"
local CERTKEY_KEY_PREFIX = "kong_acme:cert_key:"

local LOCK_TIMEOUT = 30 -- in seconds

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

local function cached_get(storage, key, deserializer, ttl, neg_ttl)
  local cache_key = kong.db.acme_storage:cache_key(key)
  return kong.cache:get(cache_key, {
    l1_serializer = deserializer,
    ttl = ttl,
    neg_ttl = neg_ttl,
  }, storage.get, storage, key)
end

local function new_storage_adapter(conf)
  local storage = conf.storage
  if not storage then
    return nil, "storage is nil"
  end
  local storage_config = conf.storage_config[storage]
  if not storage_config then
    return nil, storage .. " is not defined in plugin storage config"
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

  -- TODO: let acme accept initlizaed storage table alternatively
  return acme.new({
    account_email = conf.account_email,
    account_key = account.key,
    api_uri = conf.api_uri,
    storage_adapter = storage_full_path,
    storage_config = conf.storage_config[conf.storage],
  })
end

local function order(acme_client, host, key, cert_type)
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
      key = util.create_pkey(4096, 'RSA')
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

-- idempotent routine for updating sni and certificate in kong db
local function save(host, key, cert)
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
    kong.log.err("can't create storage adapter: ", err)
    return
  end
  local lock_key = "kong_acme:update_lock:" .. host
  -- TODO: wait longer?
  -- This goes to the backend storage and may bring pressure, add a first pass shm cache?
  local err = st:add(lock_key, "placeholder", LOCK_TIMEOUT)
  if err then
    kong.log.info("update_certificate for ", host, " is already running: ", err)
    return
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
  cert, key, err = order(acme_client, host, key, conf.cert_type)
  if not err then
    if dbless then
      -- in dbless mode, we don't actively release lock
      -- since we don't implement an IPC to purge potentially negatively
      -- cached cert/key in other node, we set the cache to be same as
      -- lock timeout, so that multiple node will not try to update certificate
      -- at the same time because they are all seeing default cert is served
      return st:set(CERTKEY_KEY_PREFIX .. host, cjson.encode({
        key = key,
        cert = cert,
      }))
    else
      err = save(host, key, cert)
    end
  end
::update_certificate_error::
  local err_del = st:delete(lock_key)
  if err_del then
    kong.log.warn("failed to delete update_certificate lock for ", host, ": ", err_del)
  end
  return err
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
    local host, sni_entity, key
    local clean_renew_conf = false
    local renew_conf, err = st:get(renew_conf_key)
    if err then
      kong.log.err("can't read renew conf: ", err)
      goto renew_continue
    end
    renew_conf = cjson.decode(renew_conf)

    host = renew_conf.host
    if renew_conf.expire_at - 86400 * conf.renew_threshold_days > ngx.time() then
      kong.log.info("certificate for host ", host, " is not due for renewal")
      goto renew_continue
    end

    -- for dbless mode, skip looking up cert key from kong
    -- instead, load it from storage and verify if it's been deleted outside of kong
    if dbless then
      local certkey, err = st:get(CERTKEY_KEY_PREFIX .. host)
      -- generally, we want to skip the current renewal if we can't verify if
      -- the cert not needed anymore. and delete the renew conf if we do see the
      -- cert is deleted
      if err then
        kong.log.err("can't read certificate of host:", host, " from storage:", err)
        goto renew_continue
      elseif not certkey then
        kong.log.warn("certificate for host ", host, " is deleted from storage, deleting renew config")
        clean_renew_conf = true
        goto renew_continue
      end
      certkey = cjson.decode(certkey)
      key = certkey and certkey.key

      goto renew_dbless
    end

    sni_entity, err = kong.db.snis:select_by_name(host)
    if err then
      kong.log.err("can't read SNI entity of host:", host, " : ", err)
      goto renew_continue
    elseif not sni_entity then
      kong.log.warn("SNI ", host, " is deleted from Kong, deleting renew config")
      clean_renew_conf = true
      goto renew_continue
    end

    if sni_entity and sni_entity.certificate then
      local cert_entity, err = kong.db.certificates:select({ id = sni_entity.certificate.id })
      if err then
        kong.log.info("can't read certificate ", sni_entity.certificate.id, " from db",
                      ", deleting renew config")
        goto renew_continue
      elseif not cert_entity then
        kong.log.warn("certificate for SNI ", host, " is deleted from Kong, deleting renew config")
        clean_renew_conf = true
        goto renew_continue
      end
      local crt, err = x509.new(cert_entity.cert)
      if err then
        kong.log.info("can't parse cert stored in kong: ", err)
      elseif crt.get_not_after() - 86400 * conf.renew_threshold_days > ngx.time() then
        kong.log.info("certificate for host ", host, " is not due for renewal (DAO)")
        goto renew_continue
      end

      if cert_entity then
        key = cert_entity.key
      end
    end
    if not key then
      kong.log.info("previous key is not defined, creating new key")
    end

::renew_dbless::

    kong.log.info("renew certificate for host ", host)
    err = update_certificate(conf, host, key)
    if err then
      kong.log.err("failed to renew certificate: ", err)
      return
    end

::renew_continue::
    if clean_renew_conf then
      err = st:delete(renew_conf_key)
      if err then
        kong.log.warn("error deleting unneeded renew config key \"", renew_conf_key, "\"")
      end
    end
  end

end

local function renew_certificate(premature)
  if premature then
    return
  end

  for plugin, err in kong.db.plugins:each(1000,
        { cache_key = "acme", }) do
    if err then
      kong.log.warn("error fetching plugin: ", err)
    end

    if plugin.name ~= "acme" then
      goto plugin_iterator_continue
    end

    kong.log.info("renew storage configured in acme plugin: ", plugin.id)
    renew_certificate_storage(plugin.config)
::plugin_iterator_continue::
  end
end


local function deserialize_certkey(j)
  j = cjson.decode(j)
  if not j.key or not j.key then
    return nil, "key or cert found in storage"
  end
  local cert, err = ngx_ssl.cert_pem_to_der(j.cert)
  if err then
    return nil, err
  end
  local key, err = ngx_ssl.priv_key_pem_to_der(j.key)
  if err then
    return nil, err
  end
  return {
    key = key,
    cert = cert,
  }
end

local function load_certkey(conf, host)
  local _, st, err = new_storage_adapter(conf)
  if err then
    return nil, err
  end
  -- see L218: we set neg ttl to be same as LOCK_TIMEOUT
  return cached_get(st,
    CERTKEY_KEY_PREFIX .. host, deserialize_certkey,
    nil, LOCK_TIMEOUT
  )
end

return {
  new = new,
  create_account = create_account,
  update_certificate = update_certificate,
  renew_certificate = renew_certificate,
  store_renew_config = store_renew_config,
  -- for dbless
  load_certkey = load_certkey,

  -- for test only
  _save = save,
  _order = order,
  _account_name = account_name,
  _renew_key_prefix = RENEW_KEY_PREFIX,
  _renew_certificate_storage = renew_certificate_storage,
}
