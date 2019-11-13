local acme = require "resty.acme.client"
local util = require "resty.acme.util"

local LE_API = "https://acme-v02.api.letsencrypt.org"
local LE_STAGING_API = "https://acme-staging-v02.api.letsencrypt.org"

-- TODO: cache me (note race condition over internal http client)
local function new(conf)
  local storage = conf.storage
  local storage_config = conf.storage_config[storage]
  if not storage_config then
    return nil, (storage or "nil") .. " is not defined in plugin storage config"
  end
  if storage == "kong" then
    storage = "kong.plugins.letsencrypt.storage.kong"
  end

  return acme.new({
    account_key = conf.account_key,
    account_email = conf.account_email,
    api_uri = conf.staging and LE_STAGING_API or LE_API,
    storage_adapter = storage,
    storage_config = storage_config,
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

local function update_certificate(acme_client, host, key, cert_type)
  local lock_key = "letsencrypt:update:" .. host
  -- TODO: wait longer?
  -- This goes to the backend storage and may bring pressure, add a first pass shm cache?
  local err = acme_client.storage:add(lock_key, "placeholder", 30)
  if err then
    kong.log.info("update_certificate for ", host, " is already running: ", err)
    return
  end
  local cert, key, err = order(acme_client, host, key, cert_type)
  if not err then
    err = save(host, key, cert)
  end
  local err_del = acme_client.storage:delete(lock_key)
  if err_del then
    kong.log.warn("failed to delete update_certificate lock for ", host, ": ", err_del)
  end
  return err
end

return {
  new = new,
  update_certificate = update_certificate,
  -- for test only
  _save = save,
  _order = order,
}
