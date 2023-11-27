local utils        = require "kong.tools.utils"
local balancer     = require "kong.runloop.balancer"
local workspaces   = require "kong.workspaces"


local kong         = kong
local unpack       = unpack
local ipairs       = ipairs
local tonumber     = tonumber
local fmt          = string.format
local utils_split  = utils.split


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
  core_cache     = kong.core_cache
  worker_events  = kong.worker_events
  cluster_events = kong.cluster_events

  -- events dispatcher
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


local declarative_reconfigure_notify
local stream_reconfigure_listener
do
  local buffer = require "string.buffer"

  -- `kong.configuration.prefix` is already normalized to an absolute path,
  -- but `ngx.config.prefix()` is not
  local PREFIX = kong and kong.configuration and
                 kong.configuration.prefix or
                 require("pl.path").abspath(ngx.config.prefix())
  local STREAM_CONFIG_SOCK = "unix:" .. PREFIX .. "/stream_config.sock"
  local IS_HTTP_SUBSYSTEM  = ngx.config.subsystem == "http"

  local function broadcast_reconfigure_event(data)
    return kong.worker_events.post("declarative", "reconfigure", data)
  end

  declarative_reconfigure_notify = function(reconfigure_data)

    -- call reconfigure_handler in each worker's http subsystem
    local ok, err = broadcast_reconfigure_event(reconfigure_data)
    if ok ~= "done" then
      return nil, "failed to broadcast reconfigure event: " .. (err or ok)
    end

    -- only http should notify stream
    if not IS_HTTP_SUBSYSTEM or
       #kong.configuration.stream_listeners == 0
    then
      return true
    end

    -- update stream if necessary

    local str, err = buffer.encode(reconfigure_data)
    if not str then
      return nil, err
    end

    local sock = ngx.socket.tcp()
    ok, err = sock:connect(STREAM_CONFIG_SOCK)
    if not ok then
      return nil, err
    end

    -- send to stream_reconfigure_listener()

    local bytes
    bytes, err = sock:send(str)
    sock:close()

    if not bytes then
      return nil, err
    end

    assert(bytes == #str,
           "incomplete reconfigure data sent to the stream subsystem")

    return true
  end

  stream_reconfigure_listener = function()
    local sock, err = ngx.req.socket()
    if not sock then
      ngx.log(ngx.CRIT, "unable to obtain request socket: ", err)
      return
    end

    local data, err = sock:receive("*a")
    if not data then
      ngx.log(ngx.CRIT, "unable to receive reconfigure data: ", err)
      return
    end

    local reconfigure_data, err = buffer.decode(data)
    if not reconfigure_data then
      ngx.log(ngx.ERR, "failed to decode reconfigure data: ", err)
      return
    end

    -- call reconfigure_handler in each worker's stream subsystem
    local ok, err = broadcast_reconfigure_event(reconfigure_data)
    if ok ~= "done" then
      ngx.log(ngx.ERR, "failed to rebroadcast reconfigure event in stream: ", err or ok)
    end
  end
end


return {
  -- runloop/handler.lua
  register_events = register_events,

  -- db/declarative/import.lua
  declarative_reconfigure_notify = declarative_reconfigure_notify,

  -- init.lua
  stream_reconfigure_listener = stream_reconfigure_listener,

  -- exposed only for tests
  _register_balancer_events = _register_balancer_events,
}
