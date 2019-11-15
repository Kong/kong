local acme = require "resty.acme.client"
local util = require "resty.acme.util"

local cjson = require "cjson"

local LE_API = "https://acme-v02.api.letsencrypt.org"
local LE_STAGING_API = "https://acme-staging-v02.api.letsencrypt.org"

local renew_key_prefix = "kong_letsencrypt:renew_config:"

local function account_name(conf)
  return "kong_letsencrypt:account:" ..(conf.staging and "staging:" or "prod:") ..
                      ngx.encode_base64(conf.account_email)
end

local function deserialize_account(j)
  j = cjson.decode(j)
  if not j.key then
    return nil, "key found in account"
  end
  return j
end

local function cached_get(storage, key, deserializer)
  local cache_key = kong.db.letsencrypt_storage:cache_key(key)
  return kong.cache:get(cache_key, {
    l1_serializer = deserializer,
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
    storage = "kong.plugins.letsencrypt.storage.kong"
  else
    storage = "resty.acme.storage." .. storage
  end
  local lib = require(storage)
  local st, err = lib.new(storage_config)
  return storage, st, err
end

-- TODO: cache me (note race condition over internal http client)
local function new(conf)
  local storage, st, err = new_storage_adapter(conf)
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
    api_uri = conf.staging and LE_STAGING_API or LE_API,
    storage_adapter = storage,
    storage_config = conf.storage_config[storage],
  })
end

-- idempotent routine for updating sni and certificate in kong db
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

local function save(host, key, cert)
  local cert_entity, err = kong.db.certificates:insert({
    cert = cert,
    key = key,
    tags = { "managed-by-letsencrypt" },
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
    tags = { "managed-by-letsencrypt" },
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
  -- Note: we don't distinguish staging because host is unique in Kong SNIs
  err = st:set(renew_key_prefix .. host, cjson.encode({
    host = host,
    conf = conf,
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
  local acme_client, err = new(conf)
  if err then
    return err
  end
  local lock_key = "kong_letsencrypt:update_lock:" .. host
  -- TODO: wait longer?
  -- This goes to the backend storage and may bring pressure, add a first pass shm cache?
  local err = acme_client.storage:add(lock_key, "placeholder", 30)
  if err then
    kong.log.info("update_certificate for ", host, " is already running: ", err)
    return
  end
  local cert, key, err = order(acme_client, host, key, conf.cert_type)
  if not err then
    err = save(host, key, cert)
  end
  local err_del = acme_client.storage:delete(lock_key)
  if err_del then
    kong.log.warn("failed to delete update_certificate lock for ", host, ": ", err_del)
  end
  return err
end

local function renew_certificate(premature, conf)
  if premature then
    return
  end
  local _, st, err = new_storage_adapter(conf)
  if err then
    kong.log.err("can't create storage adapter: ", err)
    return
  end

  local keys, err = st:list(renew_key_prefix)
  if err then
    kong.log.err("can't list renew hosts: ", err)
    return
  end
  for _, key in ipairs(keys) do
    local renew_conf, err = st:get(key)
    if err then
      kong.log.err("can't read renew conf: ", err)
      goto renew_continue
    end
    renew_conf = cjson.decode(renew_conf)

    local host = renew_conf.host
    if renew_conf.expire_at - 86400 * conf.renew_threshold_days > ngx.time() then
      kong.log.info("certificate for host ", host, " is not due for renewal")
      goto renew_continue
    end

    local sni_entity, err = kong.db.snis:select_by_name(host)
    if err then
      kong.log.err("can't read SNI entity of host:", host, " : ", err)
      goto renew_continue
    elseif not sni_entity then
      kong.log.err("SNI ", host, " is deleted from Kong, aborting")
      goto renew_continue
    end
    local key
    if sni_entity.certificate then
      local cert_entity, err = kong.db.certificates:select({ id = sni_entity.certificate.id })
      if err then
        kong.log.info("unable read certificate ", sni_entity.certificate.id, " from db")
      elseif cert_entity then
        key = cert_entity.key
      end
    end
    if not key then
      kong.log.info("previous key is not defined, creating new key")
    end

    kong.log.info("create new certificate for host ", host)
    err = update_certificate(conf, host, key)
    if err then
      kong.log.err("failed to update certificate: ", err)
      return
    end
::renew_continue::
  end

end

return {
  new = new,
  create_account = create_account,
  update_certificate = update_certificate,
  renew_certificate = renew_certificate,
  store_renew_config = store_renew_config,

  -- for test only
  _save = save,
  _order = order,
  _account_name = account_name,
}
