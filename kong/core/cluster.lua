local cache = require "kong.tools.database_cache"
local singletons = require "kong.singletons"

local KEEPALIVE_INTERVAL = 30
local KEEPALIVE_KEY = "events:keepalive"
local ASYNC_AUTOJOIN_INTERVAL = 3
local ASYNC_AUTOJOIN_RETRIES = 20 -- Try for max a minute (3s * 20)
local ASYNC_AUTOJOIN_KEY = "events:autojoin"

local function log_error(...)
  ngx.log(ngx.WARN, "[cluster] ", ...)
end

local function log_debug(...)
  ngx.log(ngx.DEBUG, "[cluster] ", ...)
end

local function get_lock(key, interval)
  -- the lock is held for the whole interval to prevent multiple
  -- worker processes from sending the test request simultaneously.
  -- here we substract the lock expiration time by 1ms to prevent
  -- a race condition with the next timer event.
  local ok, err = cache.rawadd(key, true, interval - 0.001)
  if not ok then
    return nil, err
  end
  return true
end

local function create_timer(at, cb)
  local ok, err = ngx.timer.at(at, cb)
  if not ok then
    log_error("failed to create timer: ", err)
  end
end

local function async_autojoin(premature)
  if premature then return end

  -- If this node is the only node in the cluster, but other nodes are present, then try to join them
  -- This usually happens when two nodes are started very fast, and the first node didn't write his
  -- information into the datastore yet. When the second node starts up, there is nothing to join yet.
  local ok, err = get_lock(ASYNC_AUTOJOIN_KEY, ASYNC_AUTOJOIN_INTERVAL)
  if ok then
    log_debug("auto-joining")
    -- If the current member count on this node's cluster is 1, but there are more than 1 active nodes in
    -- the DAO, then try to join them
    local count, err = singletons.dao.nodes:count()
    if err then
      log_error(tostring(err))
    elseif count > 1 then
      local members, err = singletons.serf:members()
      if err then
        log_error(tostring(err))
      elseif #members < 2 then
        -- Trigger auto-join
        local _, err = singletons.serf:autojoin()
        if err then
          log_error(tostring(err))
        end
      else
        return -- The node is already in the cluster and no need to continue
      end
    end

    -- Create retries counter key if it doesn't exist
    if not cache.get(cache.autojoin_retries_key()) then
      cache.rawset(cache.autojoin_retries_key(), 0)
    end

    local autojoin_retries = cache.incr(cache.autojoin_retries_key(), 1) -- Increment retries counter
    if (autojoin_retries < ASYNC_AUTOJOIN_RETRIES) then
      create_timer(ASYNC_AUTOJOIN_INTERVAL, async_autojoin)
    end
  elseif err ~= "exists" then
    log_error(err)
  end
end

local function send_keepalive(premature)
  if premature then return end

  local ok, err = get_lock(KEEPALIVE_KEY, KEEPALIVE_INTERVAL)
  if ok then
    log_debug("sending keepalive")
    -- Send keepalive
    local nodes, err = singletons.dao.nodes:find_all {
      name = singletons.serf.node_name
    }
    if err then
      log_error(tostring(err))
    elseif #nodes == 1 then
      local node = nodes[1]
      local _, err = singletons.dao.nodes:update(node, node, {
        ttl = singletons.configuration.cluster_ttl_on_failure, 
        quiet = true
      })
      if err then
        log_error(tostring(err))
      end
    end
  elseif err ~= "exists" then
    log_error(err)
  end

  create_timer(KEEPALIVE_INTERVAL, send_keepalive)
end

return {
  init_worker = function()
    create_timer(KEEPALIVE_INTERVAL, send_keepalive)
    create_timer(ASYNC_AUTOJOIN_INTERVAL, async_autojoin) -- Only execute one time
  end
}