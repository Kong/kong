local utils        = require "kong.tools.utils"
local constants    = require "kong.constants"
local certificate  = require "kong.runloop.certificate"
local balancer     = require "kong.runloop.balancer"
local workspaces   = require "kong.workspaces"
local wasm         = require "kong.runloop.wasm"


local kong         = kong
local unpack       = unpack
local ipairs       = ipairs
local tonumber     = tonumber
local fmt          = string.format
local utils_split  = utils.split


local ngx   = ngx
local null  = ngx.null
local log   = ngx.log
local ERR   = ngx.ERR
local CRIT  = ngx.CRIT
local DEBUG = ngx.DEBUG


local ENTITY_CACHE_STORE = constants.ENTITY_CACHE_STORE


-- init in register_events()
local db
local kong_cache
local core_cache
local worker_events
local cluster_events


-- event: "crud", "targets"
local function crud_targets_handler(data)
  local operation = data.operation
  local target = data.entity

  -- => to worker_events: balancer_targets_handler
  local ok, err = worker_events.post("balancer", "targets", {
      operation = operation,
      entity = target,
    })
  if not ok then
    log(ERR, "failed broadcasting target ", operation, " to workers: ", err)
  end

  -- => to cluster_events: cluster_balancer_targets_handler
  local key = fmt("%s:%s", operation, target.upstream.id)
  ok, err = cluster_events:broadcast("balancer:targets", key)
  if not ok then
    log(ERR, "failed broadcasting target ", operation, " to cluster: ", err)
  end
end


-- event: "crud", "upstreams"
local function crud_upstreams_handler(data)
  local operation = data.operation
  local upstream = data.entity

  if not upstream.ws_id then
    log(DEBUG, "Event crud ", operation, " for upstream ", upstream.id,
        " received without ws_id, adding.")
    upstream.ws_id = workspaces.get_workspace_id()
  end

  -- => to worker_events: balancer_upstreams_handler
  local ok, err = worker_events.post("balancer", "upstreams", {
      operation = operation,
      entity = upstream,
    })
  if not ok then
    log(ERR, "failed broadcasting upstream ",
      operation, " to workers: ", err)
  end

  -- => to cluster_events: cluster_balancer_upstreams_handler
  local key = fmt("%s:%s:%s:%s", operation, upstream.ws_id, upstream.id, upstream.name)
  local ok, err = cluster_events:broadcast("balancer:upstreams", key)
  if not ok then
    log(ERR, "failed broadcasting upstream ", operation, " to cluster: ", err)
  end
end


-- event: "balancer", "upstreams"
local function balancer_upstreams_handler(data)
  local operation = data.operation
  local upstream = data.entity

  if not upstream.ws_id then
    log(CRIT, "Operation ", operation, " for upstream ", upstream.id,
        " received without workspace, discarding.")
    return
  end

  core_cache:invalidate_local("balancer:upstreams")
  core_cache:invalidate_local("balancer:upstreams:" .. upstream.id)

  -- => to balancer update
  balancer.on_upstream_event(operation, upstream)
end


-- event: "balancer", "targets"
local function balancer_targets_handler(data)
  -- => to balancer update
  balancer.on_target_event(data.operation, data.entity)
end


-- cluster event: "balancer:targets"
local function cluster_balancer_targets_handler(data)
  local operation, key = unpack(utils_split(data, ":"))

  local entity = "all"
  if key ~= "all" then
    entity = {
      upstream = { id = key },
    }
  end

  -- => to worker_events: balancer_targets_handler
  local ok, err = worker_events.post("balancer", "targets", {
      operation = operation,
      entity = entity,
    })
  if not ok then
    log(ERR, "failed broadcasting target ", operation, " to workers: ", err)
  end
end


local function cluster_balancer_post_health_handler(data)
  local pattern = "([^|]+)|([^|]*)|([^|]+)|([^|]+)|([^|]+)|(.*)"
  local hostname, ip, port, health, id, name = data:match(pattern)

  port = tonumber(port)
  local upstream = { id = id, name = name }
  if ip == "" then
    ip = nil
  end

  local _, err = balancer.post_health(upstream, hostname, ip, port, health == "1")
  if err then
    log(ERR, "failed posting health of ", name, " to workers: ", err)
  end
end


local function cluster_balancer_upstreams_handler(data)
  local operation, ws_id, id, name = unpack(utils_split(data, ":"))
  local entity = {
    id = id,
    name = name,
    ws_id = ws_id,
  }

  -- => to worker_events: balancer_upstreams_handler
  local ok, err = worker_events.post("balancer", "upstreams", {
      operation = operation,
      entity = entity,
    })
  if not ok then
    log(ERR, "failed broadcasting upstream ", operation, " to workers: ", err)
  end
end


local function dao_crud_handler(data)
  local schema = data.schema
  if not schema then
    log(ERR, "[events] missing schema in crud subscriber")
    return
  end

  local entity = data.entity
  if not entity then
    log(ERR, "[events] missing entity in crud subscriber")
    return
  end

  -- invalidate this entity anywhere it is cached if it has a
  -- caching key

  local schema_name = schema.name

  local cache_key = db[schema_name]:cache_key(entity)
  local cache_obj = kong[ENTITY_CACHE_STORE[schema_name]]

  if cache_key then
    cache_obj:invalidate(cache_key)
  end

  -- if we had an update, but the cache key was part of what was updated,
  -- we need to invalidate the previous entity as well

  local old_entity = data.old_entity
  if old_entity then
    local old_cache_key = db[schema_name]:cache_key(old_entity)
    if old_cache_key and cache_key ~= old_cache_key then
      cache_obj:invalidate(old_cache_key)
    end
  end

  local operation = data.operation
  if not operation then
    log(ERR, "[events] missing operation in crud subscriber")
    return
  end

  -- public worker events propagation

  local entity_channel           = schema.table or schema_name
  local entity_operation_channel = fmt("%s:%s", entity_channel, operation)

  -- crud:routes
  local ok, err = worker_events.post_local("crud", entity_channel, data)
  if not ok then
    log(ERR, "[events] could not broadcast crud event: ", err)
    return
  end

  -- crud:routes:create
  ok, err = worker_events.post_local("crud", entity_operation_channel, data)
  if not ok then
    log(ERR, "[events] could not broadcast crud event: ", err)
    return
  end
end


local function crud_routes_handler()
  log(DEBUG, "[events] Route updated, invalidating router")
  core_cache:invalidate("router:version")
end


local function crud_services_handler(data)
  if data.operation == "create" or data.operation == "delete" then
    return
  end

  -- no need to rebuild the router if we just added a Service
  -- since no Route is pointing to that Service yet.
  -- ditto for deletion: if a Service if being deleted, it is
  -- only allowed because no Route is pointing to it anymore.
  log(DEBUG, "[events] Service updated, invalidating router")
  core_cache:invalidate("router:version")
end


local function crud_plugins_handler(data)
  log(DEBUG, "[events] Plugin updated, invalidating plugins iterator")
  core_cache:invalidate("plugins_iterator:version")
end


local function crud_snis_handler(data)
  log(DEBUG, "[events] SNI updated, invalidating cached certificates")

  local sni = data.old_entity or data.entity
  local sni_name = sni.name
  local sni_wild_pref, sni_wild_suf = certificate.produce_wild_snis(sni_name)
  core_cache:invalidate("snis:" .. sni_name)

  if sni_wild_pref then
    core_cache:invalidate("snis:" .. sni_wild_pref)
  end

  if sni_wild_suf then
    core_cache:invalidate("snis:" .. sni_wild_suf)
  end
end


local function crud_consumers_handler(data)
  workspaces.set_workspace(data.workspace)

  local old_entity = data.old_entity
  local old_username
  if old_entity then
    old_username = old_entity.username
    if old_username and old_username ~= null and old_username ~= "" then
      kong_cache:invalidate(db.consumers:cache_key(old_username))
    end
  end

  local entity = data.entity
  if entity then
    local username = entity.username
    if username and username ~= null and username ~= "" and username ~= old_username then
      kong_cache:invalidate(db.consumers:cache_key(username))
    end
  end
end


local function crud_wasm_handler(data, schema_name)
  if not wasm.enabled() then
    return
  end

  -- cache is invalidated on service/route deletion to ensure we don't
  -- have oprhaned filter chain data cached
  local is_delete = data.operation == "delete"
               and (schema_name == "services"
                    or schema_name == "routes")

  local updated = schema_name == "filter_chains" or is_delete

  if updated then
    log(DEBUG, "[events] wasm filter chains updated, invalidating cache")
    core_cache:invalidate("filter_chains:version")
  end
end


local LOCAL_HANDLERS = {
  { "dao:crud", nil         , dao_crud_handler },

  -- local events (same worker)
  { "crud"    , "routes"    , crud_routes_handler },
  { "crud"    , "services"  , crud_services_handler },
  { "crud"    , "plugins"   , crud_plugins_handler },

  -- SSL certs / SNIs invalidations
  { "crud"    , "snis"      , crud_snis_handler },

  -- Consumers invalidations
  -- As we support conifg.anonymous to be configured as Consumer.username,
  -- so add an event handler to invalidate the extra cache in case of data inconsistency
  { "crud"    , "consumers" , crud_consumers_handler },

  { "crud"    , "filter_chains"  , crud_wasm_handler },
  { "crud"    , "services"       , crud_wasm_handler },
  { "crud"    , "routes"         , crud_wasm_handler },
}


local BALANCER_HANDLERS = {
  { "crud"    , "targets"   , crud_targets_handler },
  { "crud"    , "upstreams" , crud_upstreams_handler },

  { "balancer", "targets"   , balancer_targets_handler },
  { "balancer", "upstreams" , balancer_upstreams_handler },
}


local CLUSTER_HANDLERS = {
  -- target updates
  { "balancer:targets"    , cluster_balancer_targets_handler },
  -- manual health updates
  { "balancer:post_health", cluster_balancer_post_health_handler },
  -- upstream updates
  { "balancer:upstreams"  , cluster_balancer_upstreams_handler },
}


local function subscribe_worker_events(source, event, handler)
  worker_events.register(handler, source, event)
end


local function subscribe_cluster_events(source, handler)
  cluster_events:subscribe(source, handler)
end


local function register_local_events()
  for _, v in ipairs(LOCAL_HANDLERS) do
    local source  = v[1]
    local event   = v[2]
    local handler = v[3]

    subscribe_worker_events(source, event, handler)
  end
end


local function register_balancer_events()
  for _, v in ipairs(BALANCER_HANDLERS) do
    local source  = v[1]
    local event   = v[2]
    local handler = v[3]

    subscribe_worker_events(source, event, handler)
  end

  for _, v in ipairs(CLUSTER_HANDLERS) do
    local source  = v[1]
    local handler = v[2]

    subscribe_cluster_events(source, handler)
  end
end


local function register_for_db()
  -- initialize local local_events hooks
  kong_cache     = kong.cache
  core_cache     = kong.core_cache
  worker_events  = kong.worker_events
  cluster_events = kong.cluster_events

  -- events dispatcher

  register_local_events()

  register_balancer_events()
end


local function register_for_dbless(reconfigure_handler)
  -- initialize local local_events hooks
  worker_events = kong.worker_events

  subscribe_worker_events("declarative", "reconfigure", reconfigure_handler)
end


local function register_events(reconfigure_handler)
  -- initialize local local_events hooks
  db = kong.db

  if db.strategy == "off" then
    -- declarative config updates
    register_for_dbless(reconfigure_handler)
    return
  end

  register_for_db()
end


local function _register_balancer_events(f)
  register_balancer_events = f
end


return {
  register_events = register_events,

  -- exposed only for tests
  _register_balancer_events = _register_balancer_events,
}
