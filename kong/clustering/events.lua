local type = type
local assert = assert


local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_DEBUG = ngx.DEBUG


local _log_prefix = "[clustering] "


local cluster_events
local worker_events


-- "clustering:push_config" => handle_clustering_push_config_event()
-- "dao:crud"               => handle_dao_crud_event()

-- handle_clustering_push_config_event() | handle_dao_crud_event() =>
--    post_push_config_event() =>
--      post("clustering", "push_config") => handler in CP =>
--        push_config_semaphore => push_config_loop() => push_config()


-- Sends "clustering", "push_config" to all workers in the same node, including self
local function post_push_config_event()
  local res, err = worker_events.post("clustering", "push_config")
  if not res then
    ngx_log(ngx_ERR, _log_prefix, "unable to broadcast event: ", err)
  end
end


-- Handles "clustering:push_config" cluster event
local function handle_clustering_push_config_event(data)
  ngx_log(ngx_DEBUG, _log_prefix, "received clustering:push_config event for ", data)
  post_push_config_event()
end


-- Handles "dao:crud" worker event and broadcasts "clustering:push_config" cluster event
local function handle_dao_crud_event(data)
  if type(data) ~= "table" or data.schema == nil or data.schema.db_export == false then
    return
  end

  cluster_events:broadcast("clustering:push_config", data.schema.name .. ":" .. data.operation)

  -- we have to re-broadcast event using `post` because the dao
  -- events were sent using `post_local` which means not all workers
  -- can receive it
  post_push_config_event()
end


local function init_cp()
  cluster_events = assert(kong.cluster_events)
  worker_events  = assert(kong.worker_events)

  -- The "clustering:push_config" cluster event gets inserted in the cluster when there's
  -- a crud change (like an insertion or deletion). Only one worker per kong node receives
  -- this callback. This makes such node post push_config events to all the cp workers on
  -- its node
  cluster_events:subscribe("clustering:push_config", handle_clustering_push_config_event)

  -- The "dao:crud" event is triggered using post_local, which eventually generates an
  -- ""clustering:push_config" cluster event. It is assumed that the workers in the
  -- same node where the dao:crud event originated will "know" about the update mostly via
  -- changes in the cache shared dict. Since data planes don't use the cache, nodes in the same
  -- kong node where the event originated will need to be notified so they push config to
  -- their data planes
  worker_events.register(handle_dao_crud_event, "dao:crud")
end


local function clustering_push_config(handler)
  worker_events.register(handler, "clustering", "push_config")
end


local function init_dp()
  worker_events  = assert(kong.worker_events)
end


local function clustering_recv_config(handler)
  worker_events.register(handler, "clustering", "recv_config")
end


return {
  init_cp = init_cp,
  clustering_push_config = clustering_push_config,

  init_dp = init_dp,
  clustering_recv_config = clustering_recv_config,
}
