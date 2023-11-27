local kong_global = require "kong.global"
local workspaces = require "kong.workspaces"
local kong_pdk_vault = require "kong.pdk.vault"
local constants = require "kong.constants"

local null = ngx.null
local log = ngx.log
local ERR = ngx.ERR
local DEBUG = ngx.DEBUG
local ENTITY_CACHE_STORE = constants.ENTITY_CACHE_STORE


local function certificate()
  -- Need to require kong.runloop.certificate late in the game to retain testability
  return require "kong.runloop.certificate"
end


local function invalidate_wasm_filters(schema_name, operation)
  -- cache is invalidated on service/route deletion to ensure we don't
  -- have orphaned filter chain data cached
  local is_delete = operation == "delete"
          and (schema_name == "services"
          or schema_name == "routes")

  local updated = schema_name == "filter_chains" or is_delete

  if updated then
    log(DEBUG, "[events] wasm filter chains updated, invalidating cache")
    kong.core_cache:invalidate("filter_chains:version")
  end

  return updated
end


local function invalidate_ca_certificates(operation, ca)
  if operation ~= "update" then
    return
  end

  local invalidated = false

  log(DEBUG, "[events] CA certificate updated, invalidating ca certificate store caches")

  local ca_id = ca.id

  local done_keys = {}
  for _, entity in ipairs(certificate().get_ca_certificate_reference_entities()) do
    local elements, err = kong.db[entity]:select_by_ca_certificate(ca_id)
    if err then
      log(ERR, "[events] failed to select ", entity, " by ca certificate ", ca_id, ": ", err)
      return
    end

    if elements then
      for _, e in ipairs(elements) do
        local key = certificate().ca_ids_cache_key(e.ca_certificates)

        if not done_keys[key] then
          done_keys[key] = true
          kong.core_cache:invalidate(key)
          invalidated = true
        end
      end
    end
  end

  local plugin_done_keys = {}
  local plugins, err = kong.db.plugins:select_by_ca_certificate(ca_id, nil,
          certificate().get_ca_certificate_reference_plugins())
  if err then
    log(ERR, "[events] failed to select plugins by ca certificate ", ca_id, ": ", err)
    return
  end

  if plugins then
    for _, e in ipairs(plugins) do
      local key = certificate().ca_ids_cache_key(e.config.ca_certificates)

      if not plugin_done_keys[key] then
        plugin_done_keys[key] = true
        kong.cache:invalidate(key)
        invalidated = true
      end
    end
  end

  return invalidated
end


local function invalidate(operation, workspace, schema_name, entity, old_entity)
  if not kong or not kong.core_cache or not kong.core_cache.invalidate then
    return
  end

  workspaces.set_workspace(workspace)

  local invalidated = false
  local function invalidate_key(key)
    local cache_obj = kong[ENTITY_CACHE_STORE[schema_name]]
    cache_obj:invalidate(key)
    invalidated = true
  end

  -- invalidate this entity anywhere it is cached if it has a
  -- caching key

  local cache_key = kong.db[schema_name]:cache_key(entity)

  if cache_key then
    invalidate_key(cache_key)
  end

  -- if we had an update, but the cache key was part of what was updated,
  -- we need to invalidate the previous entity as well

  if old_entity then
    local old_cache_key = kong.db[schema_name]:cache_key(old_entity)
    if old_cache_key and cache_key ~= old_cache_key then
      invalidate_key(old_cache_key)
    end
  end

  if schema_name == "routes" then
    invalidate_key("router:version")

  elseif schema_name == "services" then
    if operation == "update" then

      -- no need to rebuild the router if we just added a Service
      -- since no Route is pointing to that Service yet.
      -- ditto for deletion: if a Service if being deleted, it is
      -- only allowed because no Route is pointing to it anymore.
      invalidate_key("router:version")
    end

  elseif schema_name == "snis" then
    log(DEBUG, "[events] SNI updated, invalidating cached certificates")

    local sni = old_entity or entity
    local sni_name = sni.name
    local sni_wild_pref, sni_wild_suf = certificate().produce_wild_snis(sni_name)
    invalidate_key("snis:" .. sni_name)

    if sni_wild_pref then
      invalidate_key("snis:" .. sni_wild_pref)
    end

    if sni_wild_suf then
      invalidate_key("snis:" .. sni_wild_suf)
    end

  elseif schema_name == "plugins" then
    invalidate_key("plugins_iterator:version")

  elseif schema_name == "vaults" then
    if kong_pdk_vault.invalidate_vault_entity(entity, old_entity) then
      invalidated = true
    end

  elseif schema_name == "consumers" then
    -- As we support config.anonymous to be configured as Consumer.username,
    -- so invalidate the extra cache in case of data inconsistency
    local old_username
    if old_entity then
      old_username = old_entity.username
      if old_username and old_username ~= null and old_username ~= "" then
        invalidate_key(kong.db.consumers:cache_key(old_username))
      end
    end

    if entity then
      local username = entity.username
      if username and username ~= null and username ~= "" and username ~= old_username then
        invalidate_key(kong.db.consumers:cache_key(username))
      end
    end

  elseif schema_name == "ca_certificates" then
    if invalidate_ca_certificates(operation, entity) then
      invalidated = true
    end
  end

  if invalidate_wasm_filters(schema_name, operation) then
    invalidated = true
  end

  if invalidated then
    local transaction_id = kong_global.get_current_transaction_id()
    ngx.ctx.transaction_id = transaction_id
    ngx.shared.kong:set("test:current_transaction_id", transaction_id)
  end
end

return invalidate
