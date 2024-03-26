local policy_cluster = require "kong.plugins.rate-limiting.policies.cluster"
local timestamp = require "kong.tools.timestamp"
local reports = require "kong.reports"
local redis = require "resty.redis"
local table_clear = require "table.clear"

local kong = kong
local pairs = pairs
local null = ngx.null
local ngx_time= ngx.time
local shm = ngx.shared.kong_rate_limiting_counters
local fmt = string.format

local SYNC_RATE_REALTIME = -1

local EMPTY_UUID = "00000000-0000-0000-0000-000000000000"

local EMPTY = {}

local cur_usage = {
  --[[
    [db_key][cache_key] = <integer>
  --]]
}

local cur_usage_expire_at = {
  --[[
    [db_key][cache_key] = <integer>
  --]]
}

local cur_delta = {
  --[[
    [db_key][cache_key] = <integer>
  --]]
}

local function init_tables(db_key)
  cur_usage[db_key] = cur_usage[db_key] or {}
  cur_usage_expire_at[db_key] = cur_usage_expire_at[db_key] or {}
  cur_delta[db_key] = cur_delta[db_key] or {}
end


local function is_present(str)
  return str and str ~= "" and str ~= null
end


local function get_service_and_route_ids(conf)
  conf             = conf or {}

  local service_id = conf.service_id
  local route_id   = conf.route_id

  if not service_id or service_id == null then
    service_id = EMPTY_UUID
  end

  if not route_id or route_id == null then
    route_id = EMPTY_UUID
  end

  return service_id, route_id
end


local function get_local_key(conf, identifier, period, period_date)
  local service_id, route_id = get_service_and_route_ids(conf)

  return fmt("ratelimit:%s:%s:%s:%s:%s", route_id, service_id, identifier,
             period_date, period)
end


local sock_opts = {}


local EXPIRATION = require "kong.plugins.rate-limiting.expiration"

local function get_redis_configuration(plugin_conf)
  return {
     host = plugin_conf.redis.host,
     port = plugin_conf.redis.port,
     username = plugin_conf.redis.username,
     password = plugin_conf.redis.password,
     database = plugin_conf.redis.database,
     timeout = plugin_conf.redis.timeout,
     ssl = plugin_conf.redis.ssl,
     ssl_verify = plugin_conf.redis.ssl_verify,
     server_name = plugin_conf.redis.server_name,
  }
end


local function get_db_key(conf)
  local redis_config = get_redis_configuration(conf)
  return fmt("%s:%d;%d",
             redis_config.host,
             redis_config.port,
             redis_config.database)
end


local function get_redis_connection(conf)
  local red = redis:new()
  local redis_config = get_redis_configuration(conf)
  red:set_timeout(redis_config.timeout)

  sock_opts.ssl = redis_config.ssl
  sock_opts.ssl_verify = redis_config.ssl_verify
  sock_opts.server_name = redis_config.server_name

  local db_key = get_db_key(conf)

  -- use a special pool name only if redis_config.database is set to non-zero
  -- otherwise use the default pool name host:port
  if redis_config.database ~= 0 then
    sock_opts.pool = db_key
  end

  local ok, err = red:connect(redis_config.host, redis_config.port,
                              sock_opts)
  if not ok then
    kong.log.err("failed to connect to Redis: ", err)
    return nil, db_key, err
  end

  local times, err = red:get_reused_times()
  if err then
    kong.log.err("failed to get connect reused times: ", err)
    return nil, db_key, err
  end

  if times == 0 then
    if is_present(redis_config.password) then
      local ok, err
      if is_present(redis_config.username) then
        ok, err = kong.vault.try(function(cfg)
          return red:auth(cfg.username, cfg.password)
        end, redis_config)
      else
        ok, err = kong.vault.try(function(cfg)
          return red:auth(cfg.password)
        end, redis_config)
      end
      if not ok then
        kong.log.err("failed to auth Redis: ", err)
        return nil, db_key, err
      end
    end

    if redis_config.database ~= 0 then
      -- Only call select first time, since we know the connection is shared
      -- between instances that use the same redis database

      local ok, err = red:select(redis_config.database)
      if not ok then
        kong.log.err("failed to change Redis database: ", err)
        return nil, db_key, err
      end
    end
  end

  return red, db_key, err
end

local function clear_local_counter(db_key)
  -- for config updates a db may no longer be used but this happens rarely
  -- and unlikely there will be a lot of them. So we choose to not remove the table
  -- but just clear it, as recreating the table will be more expensive
  table_clear(cur_usage[db_key])
  table_clear(cur_usage_expire_at[db_key])
  table_clear(cur_delta[db_key])
end

local function sync_to_redis(premature, conf)
  if premature then
    return
  end

  local red, db_key, err = get_redis_connection(conf)
  if not red then
    kong.log.err("[rate-limiting] failed to connect to Redis: ", err)
    clear_local_counter(db_key)
    return
  end

  red:init_pipeline()

  for cache_key, delta in pairs(cur_delta[db_key] or EMPTY) do
    red:eval([[
      local key, value, expiration = KEYS[1], tonumber(ARGV[1]), ARGV[2]
      local exists = redis.call("exists", key)
      redis.call("incrby", key, value)
      if not exists or exists == 0 then
        redis.call("expireat", key, expiration)
      end
    ]], 1, cache_key, delta, cur_usage_expire_at[db_key][cache_key])
  end

  local _, err = red:commit_pipeline()
  if err then
    kong.log.err("[rate-limiting] failed to commit increment pipeline in Redis: ", err)
    clear_local_counter(db_key)
    return
  end

  local ok, err = red:set_keepalive(10000, 100)
  if not ok then
    kong.log.err("[rate-limiting] failed to set Redis keepalive: ", err)
    clear_local_counter(db_key)
    return
  end

  -- just clear these tables and avoid creating three new tables
  clear_local_counter(db_key)
end

local plugin_sync_pending = {}
local plugin_sync_running = {}

-- It's called "rate_limited_sync" because the sync timer itself
-- is rate-limited by the sync_rate.
-- It should be easy to prove that:
-- 1. There will be at most 2 timers per worker for a plugin instance
--    at any given time, 1 syncing and 1 pending (guaranteed by the locks)
-- 2. 2 timers will at least start with a sync_rate interval apart
-- 3. A change is always picked up by a pending timer and
--    will be sync to Redis at most sync_rate interval
local function rate_limited_sync(conf, sync_func)
  local cache_key = conf.__key__ or conf.__plugin_id or "rate-limiting"
  local redis_config = get_redis_configuration(conf)

  -- a timer is pending. The change will be picked up by the pending timer
  if plugin_sync_pending[cache_key] then
    return true
  end

  -- The change may or may not be picked up by a running timer
  -- let's start a pending timer to make sure the change is picked up
  plugin_sync_pending[cache_key] = true
  return kong.timer:at(conf.sync_rate, function(premature)
    if premature then
      -- we do not clear the pending flag to prevent more timers to be started
      -- as they will also exit prematurely
      return
    end

    -- a "pending" state is never touched before the timer is started
    assert(plugin_sync_pending[cache_key])


    local tries = 0
    -- a timer is already running.
    -- the sleep time is picked to a seemingly reasonable value
    while plugin_sync_running[cache_key] do
      -- we should wait for at most 2 runs even if the connection times out
      -- when this happens, we should not clear the "running" state as it would
      -- cause a race condition;
      -- we don't want to clear the "pending" state and exit the timer either as
      -- it's equivalent to waiting for more runs
      if tries > 4 then
        kong.log.emerg("A Redis sync is blocked by a previous try. " ..
          "The previous try should have timed out but it didn't for unknown reasons.")
      end

      ngx.sleep(redis_config.timeout / 2)
      tries = tries + 1
    end

    plugin_sync_running[cache_key] = true

    plugin_sync_pending[cache_key] = nil

    -- given the condition, the counters will never be empty so no need to
    -- check for empty tables and skip the sync
    local ok, err = pcall(sync_func, premature, conf)
    if not ok then
      kong.log.err("[rate-limiting] error when syncing counters to Redis: ", err)
    end

    plugin_sync_running[cache_key] = nil
  end)
end

local function update_local_counters(conf, periods, limits, identifier, value)
  local db_key = get_db_key(conf)
  init_tables(db_key)

  for period, period_date in pairs(periods) do
    if limits[period] then
      local cache_key = get_local_key(conf, identifier, period, period_date)

      cur_delta[db_key][cache_key] = (cur_delta[db_key][cache_key] or 0) + value
    end
  end

end

return {
  ["local"] = {
    increment = function(conf, limits, identifier, current_timestamp, value)
      local periods = timestamp.get_timestamps(current_timestamp)
      for period, period_date in pairs(periods) do
        if limits[period] then
          local cache_key = get_local_key(conf, identifier, period, period_date)
          local newval, err = shm:incr(cache_key, value, 0, EXPIRATION[period])
          if not newval then
            kong.log.err("could not increment counter for period '", period, "': ", err)
            return nil, err
          end
        end
      end

      return true
    end,
    usage = function(conf, identifier, period, current_timestamp)
      local periods = timestamp.get_timestamps(current_timestamp)
      local cache_key = get_local_key(conf, identifier, period, periods[period])

      local current_metric, err = shm:get(cache_key)
      if err then
        return nil, err
      end

      return current_metric or 0
    end,
  },
  ["cluster"] = {
    increment = function(conf, limits, identifier, current_timestamp, value)
      local db = kong.db
      local service_id, route_id = get_service_and_route_ids(conf)
      local policy = policy_cluster[db.strategy]

      local ok, err = policy.increment(db.connector, limits, identifier,
                                       current_timestamp, service_id, route_id,
                                       value)

      if not ok then
        kong.log.err("cluster policy: could not increment ", db.strategy,
                     " counter: ", err)
      end

      return ok, err
    end,
    usage = function(conf, identifier, period, current_timestamp)
      local db = kong.db
      local service_id, route_id = get_service_and_route_ids(conf)
      local policy = policy_cluster[db.strategy]

      local row, err = policy.find(identifier, period, current_timestamp,
                                   service_id, route_id)

      if err then
        return nil, err
      end

      if row and row.value ~= null and row.value > 0 then
        return row.value
      end

      return 0
    end,
  },
  ["redis"] = {
    increment = function(conf, limits, identifier, current_timestamp, value)
      local periods = timestamp.get_timestamps(current_timestamp)

      if conf.sync_rate == SYNC_RATE_REALTIME then
        -- we already incremented the counter at usage()
        return true

      else
        update_local_counters(conf, periods, limits, identifier, value)
        return rate_limited_sync(conf, sync_to_redis)
      end
    end,
    usage = function(conf, identifier, period, current_timestamp)
      local periods = timestamp.get_timestamps(current_timestamp)
      local cache_key = get_local_key(conf, identifier, period, periods[period])
      local db_key = get_db_key(conf)
      init_tables(db_key)

      -- use local cache to reduce the number of redis calls
      -- also by pass the logic of incrementing the counter
      if conf.sync_rate ~= SYNC_RATE_REALTIME and cur_usage[db_key][cache_key] then
        if cur_usage_expire_at[db_key][cache_key] > ngx_time() then
          return cur_usage[db_key][cache_key] + (cur_delta[db_key][cache_key] or 0)
        end

        cur_usage[db_key][cache_key] = 0
        cur_usage_expire_at[db_key][cache_key] = periods[period] + EXPIRATION[period]
        cur_delta[db_key][cache_key] = 0

        return 0
      end

      local red, err = get_redis_connection(conf)
      if not red then
        return nil, err
      end

      reports.retrieve_redis_version(red)

      -- the usage of redis command incr instead of get is to avoid race conditions in concurrent calls
      local current_metric, err = red:eval([[
        local cache_key, expiration = KEYS[1], ARGV[1]
        local result_incr = redis.call("incr", cache_key)
        if result_incr == 1 then
          redis.call("expire", cache_key, expiration)
        end

        return result_incr - 1
      ]], 1, cache_key, EXPIRATION[period])

      if err then
        return nil, err
      end

      if current_metric == null then
        current_metric = nil
      end

      local ok, err = red:set_keepalive(10000, 100)
      if not ok then
        kong.log.err("failed to set Redis keepalive: ", err)
      end

      if conf.sync_rate ~= SYNC_RATE_REALTIME then
        cur_usage[db_key][cache_key] = current_metric or 0
        cur_usage_expire_at[db_key][cache_key] = periods[period] + EXPIRATION[period]
        -- The key was just read from Redis using `incr`, which incremented it
        -- by 1. Adjust the value to account for the prior increment.
        cur_delta[db_key][cache_key] = -1
      end

      return current_metric or 0
    end
  }
}
