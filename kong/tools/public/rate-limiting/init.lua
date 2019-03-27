local _M = {}


local floor    = math.floor
local insert   = table.insert
local ngx_log  = ngx.log
local now      = ngx.now
local time     = ngx.time
local timer_at = ngx.timer.at


local DEBUG = ngx.DEBUG
local ERR   = ngx.ERR


local locks_shm = ngx.shared.kong_cache


local new_tab
do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function(narr, nrec)
      return {}
    end
  end
end


local function log(lvl, ...)
  ngx_log(lvl, "[rate-limiting] ", ...)
end


local function calculate_weight(window_size)
  return (window_size - (time() % window_size)) / window_size
end


-- namespace configurations
local config = {
  -- default = {
    -- dict,
    -- sync_rate,
    -- strategy,
    -- seen_map,
    -- seen_map_idx,
    -- seen_map_ctr,
    -- window_sizes,
  -- }
}
_M.config = config


function _M.table_names()
  local t = {
    "rl_counters",
  }

  return t
end


local function window_floor(size, time)
  return floor(time / size) * size
end


local function fetch(premature, namespace, time, timeout)
  if premature then
    return
  end

  namespace  = namespace or "default"
  local cfg  = config[namespace]
  local dict = ngx.shared[cfg.dict]

  -- mutex so only one worker fetches from the cluster and
  -- updates our shared zone
  local lock_key = "rl-init-fetch-" .. namespace
  local ok, err  = locks_shm:add(lock_key, true, timeout)
  if not ok then
    if err ~= "exists" then
      log(ERR, "err in setting initial ratelimit fetch mutex for ",
               namespace, ": ", err)
    end

    return
  end

  -- this worker is allowed to fetch and update the sync keys
  log(DEBUG, "rl fetch mutex established on pid ", ngx.worker.pid())

  for row in cfg.strategy:get_counters(namespace, cfg.window_sizes, time) do
    local dict_key = namespace .. "|" .. row.window_start ..
                     "|" .. row.window_size .. "|" .. row.key

    log(DEBUG, "setting sync key ", dict_key)

    local ok, err = dict:set(dict_key .. "|sync", row.count)
    if not ok then
      log(ERR, "err setting sync key: ", err)
    end
  end

  if not timeout then
    locks_shm:delete(lock_key)
  end
end
_M.fetch = fetch


function _M.sync(premature, namespace)
  if premature then
    return
  end

  namespace  = namespace or "default"
  local cfg  = config[namespace]
  local dict = ngx.shared[cfg.dict]

  if cfg.kill then
    log(DEBUG, "killing ", namespace)
    return
  end

  log(DEBUG, "start sync ", namespace)

  local sync_start_now  = now()
  local sync_start_time = time()

  do
    local _, err = timer_at(cfg.sync_rate, _M.sync, namespace)
    if err then
      log(ERR, "error starting new sync timer: ", err)
    end
  end

  if cfg.seen_map_idx == 0 then
    log(DEBUG, "empty sync, do fetch")
    fetch(nil, namespace, sync_start_time, cfg.sync_rate - 0.001)
    return
  end

  -- roll over our seen keys map
  local seen_map_old_idx = cfg.seen_map_idx
  cfg.seen_map_idx = 0
  cfg.seen_map_ctr = cfg.seen_map_ctr + 1

  -- assume we'll see at least the same amount of keys next time
  cfg.seen_map[cfg.seen_map_ctr] = new_tab(seen_map_old_idx, seen_map_old_idx)

  local diffs = new_tab(seen_map_old_idx, seen_map_old_idx)

  for i = 1, seen_map_old_idx do
    local key = cfg.seen_map[cfg.seen_map_ctr - 1][i]

    log(DEBUG, "try sync ", key)

    local ok, err = locks_shm:add(key .. "|sync-lock", true, cfg.sync_rate - 0.001)
    if not ok and err ~= "exists" then
      ngx.log(ngx.WARN, "error in establishing sync-lock for ", key, ": ", err)
    end

    -- we have the lock!
    -- get the current diff, and push it
    -- before we push, set the diff to 0 so we track while we push diff + wait
    -- for sync
    if ok then
      -- figure out by how much we need to incr this key and subtract it from
      -- the running diff counter (raceless operation)
      local diff_val = dict:get(key .. "|diff")
      log(DEBUG, "neg incr ", -diff_val)
      dict:incr(key .. "|diff", -diff_val)

      -- mock what we think as the synced value so we dont lose counts
      -- since our diff counter is reduced to 0, we account for this by
      -- temporarily increasing our sync counter to make up the difference. this
      -- only lives until we have finished updating all keys upstream, and we
      -- finish the 'read' of the write-then-read strategy used here
      dict:incr(key .. "|sync", diff_val)

      log(DEBUG, "push ", key, ": ", diff_val)

      --[[
        diffs = {
          [1] = {
            key = "1.2.3.4",
            windows = {
              {
                window    = 12345610,
                size      = 60,
                diff      = 5,
                namespace = foo,
              },
              {
                window    = 12345670,
                size      = 60,
                diff      = 5,
                namespace = foo,
              },
            }
          },
          ...
          ["1.2.3.4"] = 1,
          ...
      ]]

      -- grab each element of the key string
      local p, q
      p = key:find("|", 1, true)
      local namespace = key:sub(1, p - 1)
      q = p + 1
      p = key:find("|", q, true)
      local window = key:sub(q, p - 1)
      q = p + 1
      p = key:find("|", q, true)
      local size = key:sub(q, p - 1)
      q = p + 1
      -- get everything to the end
      local rl_key = key:sub(q)

      -- now figure out if this data point already has a top-level key
      -- if so, add it to the windows member of this entry; otherwise,
      -- we create a new key in `diffs` based on this rl_key, and add
      -- the appropriate members
      local rl_key_idx = diffs[rl_key]

      if not rl_key_idx then
        rl_key_idx = #diffs + 1

        diffs[rl_key] = rl_key_idx

        diffs[rl_key_idx] = {
          key = rl_key,
          windows = {},
        }
      end

      insert(diffs[diffs[rl_key]].windows, {
        window    = tonumber(window),
        size      = tonumber(size),
        diff      = tonumber(diff_val),
        namespace = namespace,
      })
    end
  end

  -- push these diffs to the appropriate data store
  cfg.strategy:push_diffs(diffs)

  -- sleep for a bit to allow each node in the cluster to update,
  -- and the data store to reach consistency. once that's done
  -- we re-gather our synced values
  ngx.sleep(cfg.sync_rate / 20)

  local sync_end_now = now() - sync_start_now

  -- update this node's sync counters
  -- consider the amount of time we've already taken when setting
  -- the lock timeout for the next fetch
  fetch(nil, namespace, sync_start_time, cfg.sync_rate - sync_end_now - 0.001)

  -- we dont need the old map anymore
  cfg.seen_map[cfg.seen_map_ctr - 1] = nil

  log(ngx.DEBUG, "sync time ", sync_end_now)

  log(DEBUG, "end sync")
end


-- calculate the sliding window based on the tuple of key,window_size
-- we derive the weight of the previous window based on how far along into
-- the current window we are
--
-- third param cur_diff is an optional arg of the current diff of the key
-- this allows us to save a shm fetch whiling calculating
-- the sliding window from increment()
local function sliding_window(key, window_size, cur_diff, namespace, weight)
  namespace  = namespace or "default"
  local cfg  = config[namespace]
  local dict = ngx.shared[cfg.dict]

  local cur_window  = window_floor(window_size, time())
  local prev_window = cur_window - window_size

  -- incr(k, 0, 0) is a branch free way to dict:get(...) or 0
  --
  -- storing |diff and |sync counters separately sucks. we want to use
  -- the incr() operator as part of our increment() becase its atomic
  -- however, this takes a single value of type 'number'; in Lua this is
  -- a double, so we could use the upper and lower 32 bits of this data
  -- to represet diff and sync, however, the Lua bitop library only works
  -- on 32 bits, so trying to rshift down the high bits to use as a separate
  -- type is a no-op. bummer. so we're stuck with two discrete values. :/
  local cur_prefix  = namespace .. "|" .. cur_window .. "|" .. window_size ..
                      "|" .. key
  local prev_prefix = namespace .. "|" .. prev_window .. "|" .. window_size ..
                      "|" .. key

  log(DEBUG, "cur_prefix ", cur_prefix)
  log(DEBUG, "prev_prefix ", prev_prefix)

  local cur = cur_diff or dict:incr(cur_prefix .. "|diff", 0, 0)
  log(DEBUG, "cur diff: ", cur)

  cur = cur + dict:incr(cur_prefix .. "|sync", 0, 0)
  log(DEBUG, "cur sum: ", cur)

  local prev = 0

  if not weight then
    weight = calculate_weight(window_size)
  end

  if weight > 0 then
    prev = dict:incr(prev_prefix .. "|diff", 0, 0)
    log(DEBUG, "prev diff: ", prev)

    prev = prev + dict:incr(prev_prefix .. "|sync", 0, 0)
    log(DEBUG, "prev sum: ", prev)

    prev = prev * weight
    log(DEBUG, "weighted prev: ", prev)
  end

  return cur + prev
end
_M.sliding_window = sliding_window


-- increment our diff counter for this key,window
-- returns the sliding window value for this key
function _M.increment(key, window_size, value, namespace, prev_window_weight)
  namespace  = namespace or "default"
  local cfg  = config[namespace]
  local dict = ngx.shared[cfg.dict]

  local window = window_floor(window_size, time())

  -- storing keys like means its easy to work with our shared dicts,
  -- but storage consumers that do not work as a k/v store (e.g. cassandra)
  -- need to pick it apart.
  local incr_key = namespace .. "|" .. window .. "|" .. window_size .. "|" .. key

  -- increment this key
  local newval = dict:incr(incr_key .. "|diff", value, 0)

  -- and mark that we've seen it (if we're syncing in the background;
  -- if we're not syncing at all, or syncing after every increment,
  -- the worker doesnt need to track what it has seen)
  if cfg.sync_rate > 0 then
    if not cfg.seen_map[cfg.seen_map_ctr][incr_key] then
      cfg.seen_map_idx = cfg.seen_map_idx + 1
      cfg.seen_map[cfg.seen_map_ctr][cfg.seen_map_idx] = incr_key
      cfg.seen_map[cfg.seen_map_ctr][incr_key] = true
    end

  elseif cfg.sync_rate == 0 then
    -- push it up synchronously
    local diffs = {
      {
        key     = key,
        windows = {
          {
            window    = window,
            size      = window_size,
            diff      = value,
            namespace = namespace,
          }
        }
      }
    }

    -- handle our diff similarly to we do with the regular sync()
    -- note we're still using dict:incr() because other workers may
    -- be working on this dictionary at the same time, so we need to
    -- ensure we take an atomic approach
    -- TODO
    -- this needs a refactor to avoid so many shm operations
    -- this currently a bottleneck with this policy (sync_rate == 0)
    dict:incr(incr_key .. "|diff", -newval)
    dict:incr(incr_key .. "|sync", newval)

    cfg.strategy:push_diffs(diffs)
    dict:set(incr_key .. "|sync", cfg.strategy:get_window(key,
                                                          namespace,
                                                          window,
                                                          window_size))

    newval = nil -- make sliding window refetch the diff
  end

  -- how much of the previous window should we take into consideration
  local weight = prev_window_weight or calculate_weight(window_size)

  -- return the current sliding window for this key
  return sliding_window(key, window_size, newval, namespace, weight)
end


local function run_maintenance_cycle(premature, period, namespace)
  if premature then
    return
  end

  local cfg = config[namespace]
  if not cfg then
    log(DEBUG, "namespace ", namespace, " no longer exists")
    return
  end

  log(DEBUG, "starting timer for ", namespace, " cleanup at ", time() + period)
  local _, err = timer_at(period, run_maintenance_cycle, period, namespace)
  if err then
    log(ERR, "error starting new maintenance timer: ", err)
  end

  local ok, err = locks_shm:add("rl-maint-" .. namespace, true, period - 0.1)
  if not ok then
    if err ~= "exists" then
      log(ERR, "failed to execute lock acquisition: ", err)
    end

    return
  end

  local ok = cfg.strategy:purge(namespace, cfg.window_sizes, time())
  if not ok then
    log(ERR, "rate-limiting strategy maintenance cycle failed")
  end
end


function _M.new(opts)
  if type(opts) ~= "table" then
    error("opts must be a table")
  end

  local strategy_type = opts.strategy
  local namespace     = opts.namespace or "default"

  if type(namespace) ~= "string" or namespace == "" then
    error("namespace must be a valid string")
  end

  if namespace:find("|", nil, true) then
    error("namespace must not contain a pipe char")
  end

  if config[namespace] then
    error("namespace " .. namespace .. " already exists")
  end

  if type(opts.dict) ~= "string" or opts.dict == "" then
    error("given dictionary reference must be a string")
  end

  if type(opts.sync_rate) ~= "number" then
    error("sync rate must be a number")
  end

  -- load the class and instantiate it
  local strategy_class = require("kong.tools.public.rate-limiting." ..
                                 "strategies." .. strategy_type)
  config[namespace] = {
    dict         = opts.dict,
    sync_rate    = opts.sync_rate,
    strategy     = strategy_class.new(opts.db, opts.strategy_opts),
    seen_map     = {{}},
    seen_map_idx = 0,
    seen_map_ctr = 1,
    window_sizes = opts.window_sizes,
  }

  -- start maintenance timer
  do
    local period = 3600
    log(DEBUG, "starting timer for ", namespace, " cleanup at ", time() + period)
    local _, err = timer_at(period, run_maintenance_cycle, period, namespace)
    if err then
      log(ERR, "error starting new maintenance timer: ", err)
    end
  end

  return true
end


function _M.clear_config(namespace)
  if namespace then
    config[namespace] = nil

  else
    config = {}
  end
end


return _M

