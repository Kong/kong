-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local meta = require "kong.meta"
local azure = require "resty.azure"
local lrucache = require "resty.lrucache"
local fmt = string.format
local getenv = os.getenv

local AZURE_CLIENTS

local secrets_client

local function get_service_cache_key(conf)
  -- conf table cannot be used directly because
  -- it is generated every time when resolving
  -- reference
  return fmt("%s:%s:%s:%s",
        conf.vault_uri,
        conf.client_id,
        conf.tenant_id,
        conf.credentials_prefix)
end

local function init()
  AZURE_CLIENTS = lrucache.new(20)
end

local function get(conf, resource, version)
  -- we can't get the vault name or any other contextual information
  -- so use the table pointer reference __tostring method as the lookup key.
  local cache_key = get_service_cache_key(conf)
  local azure_client = AZURE_CLIENTS:get(cache_key)
  if not azure_client then
    azure_client = azure:new({
      client_id = conf.client_id,
      tenant_id = conf.tenant_id,
      envPrefix = conf.credentials_prefix,
    })
    AZURE_CLIENTS:set(cache_key, azure_client)
  end
  local vault_uri = conf.vault_uri or getenv("AZURE_VAULT_URI")
  if not vault_uri then
    return nil, "azure vault uri is required"
  end
  secrets_client = azure_client:secrets(vault_uri)

  local response, err = secrets_client:get(resource, conf.version or version)
  if err or not response then
    return nil, err
  end
  return response.value
end


return {
  name = "azure",
  VERSION = meta.core_version,
  init = init,
  get = get,
  license_required = true,
}
