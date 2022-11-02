local utils        = require "kong.tools.utils"
local balancer     = require "kong.runloop.balancer"
local workspaces   = require "kong.workspaces"
--local concurrency  = require "kong.concurrency"


local kong              = kong
local unpack            = unpack
local tonumber          = tonumber
local fmt               = string.format
local utils_split       = utils.split


local ngx   = ngx
local log   = ngx.log
local ERR   = ngx.ERR
local CRIT  = ngx.CRIT
local DEBUG = ngx.DEBUG


-- init in register_events()
local db
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
  local operation = data.operation
  local target = data.entity

  -- => to balancer update
  balancer.on_target_event(operation, target)
end


-- cluster event: "balancer:targets"
local function cluster_balancer_targets_handler(data)
  local operation, key = unpack(utils_split(data, ":"))
  local entity

  if key ~= "all" then
    entity = {
      upstream = { id = key },
    }

  else
    entity = "all"
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


local function register_balancer_events()
  -- target updates --
  -- worker_events local handler: event received from DAO
  worker_events.register(crud_targets_handler, "crud", "targets")

  -- worker_events node handler
  worker_events.register(balancer_targets_handler, "balancer", "targets")

  -- cluster_events handler
  cluster_events:subscribe("balancer:targets",
                           cluster_balancer_targets_handler)

  -- manual health updates
  cluster_events:subscribe("balancer:post_health",
                           cluster_balancer_post_health_handler)

  -- upstream updates --
  -- worker_events local handler: event received from DAO
  worker_events.register(crud_upstreams_handler, "crud", "upstreams")

  -- worker_events node handler
  worker_events.register(balancer_upstreams_handler, "balancer", "upstreams")

  cluster_events:subscribe("balancer:upstreams",
                           cluster_balancer_upstreams_handler)
end


local function register_events()
  -- initialize local local_events hooks
  db             = kong.db
  core_cache     = kong.core_cache
  worker_events  = kong.worker_events
  cluster_events = kong.cluster_events

  if db.strategy == "off" then
    db = nil -- place holder
  end

  register_balancer_events()
end


local function _register_balancer_events(f)
  register_balancer_events = f
end


return {
  register_events = register_events,

  _register_balancer_events = _register_balancer_events,
}
