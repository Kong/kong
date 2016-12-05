local singletons = require "kong.singletons"


local kong_dict = ngx.shared.kong
local timer_at = ngx.timer.at
local ngx_log = ngx.log
local ERR = ngx.ERR
local DEBUG = ngx.DEBUG


local KEEPALIVE_INTERVAL = 30
local KEEPALIVE_KEY = "events:keepalive"
local AUTOJOIN_INTERVAL = 3
local AUTOJOIN_KEY = "events:autojoin"
local AUTOJOIN_MAX_RETRIES = 20 -- Try for max a minute (3s * 20)
local AUTOJOIN_MAX_RETRIES_KEY = "autojoin_retries"


local function log(lvl, ...)
  ngx_log(lvl, "[cluster] ", ...)
end


-- Hold a lock for the whole interval (exptime) to prevent multiple
-- worker processes from sending the test request simultaneously.
-- Other workers do not need to wait until this lock is released,
-- and can ignore the event, knowing another worker is handling it.
-- We substract 1ms to the exp time to prevent a race condition
-- with the next timer event.
local function get_lock(key, exptime)
  local ok, err = kong_dict:safe_add(key, true, exptime - 0.001)
  if not ok and err ~= "exists" then
    log(ERR, "could not get lock from 'kong' shm: ", err)
  end

  return ok
end


local function create_timer(...)
  local ok, err = timer_at(...)
  if not ok then
    log(ERR, "could not create timer: ", err)
  end
end


local function autojoin_handler(premature)
  if premature then
    return
  end

  -- increase retry count by 1

  local n_retries, err = kong_dict:incr(AUTOJOIN_MAX_RETRIES_KEY, 1, 0)
  if err then
    log(ERR, "could not increment number of auto-join retries in 'kong' ",
             "shm: ", err)
    return
  end

  -- register recurring retry timer

  if n_retries < AUTOJOIN_MAX_RETRIES then
    -- all workers need to register a recurring timer, in case one of them
    -- crashes. Hence, this must be called before the `get_lock()` call.
    create_timer(AUTOJOIN_INTERVAL, autojoin_handler)
  end

  if not get_lock(AUTOJOIN_KEY, AUTOJOIN_INTERVAL) then
    return
  end

  -- auto-join nodes table

  -- If this node is the only node in the cluster, but other nodes are present, then try to join them
  -- This usually happens when two nodes are started very fast, and the first node didn't write his
  -- information into the datastore yet. When the second node starts up, there is nothing to join yet.
  log(DEBUG, "auto-joining")

  -- If the current member count on this node's cluster is 1, but there are more than 1 active nodes in
  -- the DAO, then try to join them
  local count, err = singletons.dao.nodes:count()
  if err then
    log(ERR, err)

  elseif count > 1 then
    local members, err = singletons.serf:members()
    if err then
      log(ERR, err)

    elseif #members < 2 then
      -- Trigger auto-join
      local _, err = singletons.serf:autojoin()
      if err then
        log(ERR, err)
      end

    else
      return -- The node is already in the cluster and no need to continue
    end
  end
end


local function keepalive_handler(premature)
  if premature then
    return
  end

  -- all workers need to register a recurring timer, in case one of them
  -- crashes. Hence, this must be called before the `get_lock()` call.
  create_timer(KEEPALIVE_INTERVAL, keepalive_handler)

  if not get_lock(KEEPALIVE_KEY, KEEPALIVE_INTERVAL) then
    return
  end

  log(DEBUG, "sending keepalive event to datastore")

  local nodes, err = singletons.dao.nodes:find_all {
    name = singletons.serf.node_name
  }
  if err then
    log(ERR, "could not retrieve nodes from datastore: ", err)

  elseif #nodes == 1 then
    local node = nodes[1]
    local _, err = singletons.dao.nodes:update(node, node, {
      ttl = singletons.configuration.cluster_ttl_on_failure,
      quiet = true
    })
    if err then
      log(ERR, "could not update node in datastore:", err)
    end
  end
end


return {
  init_worker = function()
    create_timer(KEEPALIVE_INTERVAL, keepalive_handler)
    create_timer(AUTOJOIN_INTERVAL, autojoin_handler)
  end
}
