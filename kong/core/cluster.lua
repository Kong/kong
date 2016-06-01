local singletons = require "kong.singletons"
local cluster_utils = require "kong.tools.cluster"
local cache = require "kong.tools.database_cache"

local resty_lock
local status, res = pcall(require, "resty.lock")
if status then
  resty_lock = res
end

local KEEPALIVE_INTERVAL = 30
local ASYNC_AUTOJOIN_INTERVAL = 3
local ASYNC_AUTOJOIN_RETRIES = 20 -- Try for max a minute (3s * 20)

local function create_timer(at, cb)
  local ok, err = ngx.timer.at(at, cb)
  if not ok then
    ngx.log(ngx.ERR, "[cluster] failed to create timer: ", err)
  end
end

local function async_autojoin(premature)
  if premature then return end

  -- If this node is the only node in the cluster, but other nodes are present, then try to join them
  -- This usually happens when two nodes are started very fast, and the first node didn't write his
  -- information into the datastore yet. When the second node starts up, there is nothing to join yet.
  if not singletons.configuration.cluster["auto-join"] then return end

  local lock = resty_lock:new("cluster_autojoin_locks", {
    exptime = ASYNC_AUTOJOIN_INTERVAL - 0.001
  })
  local elapsed = lock:lock("async_autojoin")
  if elapsed and elapsed == 0 then
    -- If the current member count on this node's cluster is 1, but there are more than 1 active nodes in
    -- the DAO, then try to join them
    local count, err = singletons.dao.nodes:count()
    if err then
      ngx.log(ngx.ERR, tostring(err))
    elseif count > 1 then
      local members, err = singletons.serf:_members()
      if err then
        ngx.log(ngx.ERR, tostring(err))
      elseif #members < 2 then
        -- Trigger auto-join
        local _, err = singletons.serf:_autojoin(cluster_utils.get_node_identifier(singletons.configuration))
        if err then
          ngx.log(ngx.ERR, tostring(err))
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
  end
end

local function send_keepalive(premature)
  if premature then return end

  local lock = resty_lock:new("cluster_locks", {
    exptime = KEEPALIVE_INTERVAL - 0.001
  })
  local elapsed = lock:lock("keepalive")
  if elapsed and elapsed == 0 then
    -- Send keepalive
    local node_name = cluster_utils.get_node_identifier(singletons.configuration)
    local nodes, err = singletons.dao.nodes:find_all {name = node_name}
    if err then
      ngx.log(ngx.ERR, tostring(err))
    elseif #nodes == 1 then
      local node = nodes[1]
      local _, err = singletons.dao.nodes:update(node, node, {ttl=singletons.configuration.cluster.ttl_on_failure})
      if err then
        ngx.log(ngx.ERR, tostring(err))
      end
    end
  end

  create_timer(KEEPALIVE_INTERVAL, send_keepalive)
end

return {
  init_worker = function()
    create_timer(KEEPALIVE_INTERVAL, send_keepalive)
    create_timer(ASYNC_AUTOJOIN_INTERVAL, async_autojoin) -- Only execute one time
  end
}
