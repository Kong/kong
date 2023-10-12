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

-- for `conf.sync_rate > 0`
local auto_sync_timer

local cur_usage = {
  --[[
    [cache_key] = <integer>
  --]]
}

local cur_usage_expire_at = {
  --[[
    [cache_key] = <integer>
  --]]
}

local cur_delta = {
  --[[
    [cache_key] = <integer>
  --]]
}


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


local function get_redis_connection(conf)
  local red = redis:new()
  red:set_timeout(conf.redis_timeout)

  sock_opts.ssl = conf.redis_ssl
  sock_opts.ssl_verify = conf.redis_ssl_verify
  sock_opts.server_name = conf.redis_server_name

  -- use a special pool name only if redis_database is set to non-zero
  -- otherwise use the default pool name host:port
  if conf.redis_database ~= 0 then
    sock_opts.pool = fmt( "%s:%d;%d",
                          conf.redis_host,
                          conf.redis_port,
                          conf.redis_database)
  end

  local ok, err = red:connect(conf.redis_host, conf.redis_port,
                              sock_opts)
  if not ok then
    kong.log.err("failed to connect to Redis: ", err)
    return nil, err
  end

  local times, err = red:get_reused_times()
  if err then
    kong.log.err("failed to get connect reused times: ", err)
    return nil, err
  end

  if times == 0 then
    if is_present(conf.redis_password) then
      local ok, err
      if is_present(conf.redis_username) then
        ok, err = kong.vault.try(function(cfg)
          return red:auth(cfg.redis_username, cfg.redis_password)
        end, conf)
      else
        ok, err = kong.vault.try(function(cfg)
          return red:auth(cfg.redis_password)
        end, conf)
      end
      if not ok then
        kong.log.err("failed to auth Redis: ", err)
        return nil, err
      end
    end

    if conf.redis_database ~= 0 then
      -- Only call select first time, since we know the connection is shared
      -- between instances that use the same redis database

      local ok, err = red:select(conf.redis_database)
      if not ok then
        kong.log.err("failed to change Redis database: ", err)
        return nil, err
      end
    end
  end

  return red
end

local function clear_local_counter()
  table_clear(cur_usage)
  table_clear(cur_usage_expire_at)
  table_clear(cur_delta)
end

local function sync_to_redis(premature, conf)
  if premature then
    return
  end

  local red, err = get_redis_connection(conf)
  if not red then
    kong.log.err("[rate-limiting] failed to connect to Redis: ", err)
    clear_local_counter()
    return
  end

  red:init_pipeline()

  for cache_key, delta in pairs(cur_delta) do
    red:eval([[
      local key, value, expiration = KEYS[1], tonumber(ARGV[1]), ARGV[2]
      local exists = redis.call("exists", key)
      redis.call("incrby", key, value)
      if not exists or exists == 0 then
        redis.call("expireat", key, expiration)
      end
    ]], 1, cache_key, delta, cur_usage_expire_at[cache_key])
  end

  local _, err = red:commit_pipeline()
  if err then
    kong.log.err("[rate-limiting] failed to commit increment pipeline in Redis: ", err)
    clear_local_counter()
    return
  end

  local ok, err = red:set_keepalive(10000, 100)
  if not ok then
    kong.log.err("[rate-limiting] failed to set Redis keepalive: ", err)
    clear_local_counter()
    return
  end

  -- just clear these tables and avoid creating three new tables
  clear_local_counter()
end

local function periodical_sync(conf, sync_func)
  if not auto_sync_timer then
    local err
    -- timer may be initialized after the module's loaded so we need to update the reference
    auto_sync_timer, err = kong.timer:named_every("rate-limiting-auto-sync", conf.sync_rate, sync_func, conf)

    if not auto_sync_timer then
      kong.log.err("failed to create timer: ", err)
      return nil, err
    end
  end

  return true
end

local function update_local_counters(conf, periods, limits, identifier, value)
  for period, period_date in pairs(periods) do
    if limits[period] then
      local cache_key = get_local_key(conf, identifier, period, period_date)

      if cur_delta[cache_key] then
        cur_delta[cache_key] = cur_delta[cache_key] + value
      else
        cur_delta[cache_key] = value
      end
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
        return periodical_sync(conf, sync_to_redis)
      end
    end,
    usage = function(conf, identifier, period, current_timestamp)
      local periods = timestamp.get_timestamps(current_timestamp)
      local cache_key = get_local_key(conf, identifier, period, periods[period])

      -- use local cache to reduce the number of redis calls
      -- also by pass the logic of incrementing the counter
      if conf.sync_rate ~= SYNC_RATE_REALTIME and cur_usage[cache_key] then
        if cur_usage_expire_at[cache_key] > ngx_time() then
          return cur_usage[cache_key] + (cur_delta[cache_key] or 0)
        end

        cur_usage[cache_key] = 0
        cur_usage_expire_at[cache_key] = periods[period] + EXPIRATION[period]
        cur_delta[cache_key] = 0

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
        cur_usage[cache_key] = current_metric or 0
        cur_usage_expire_at[cache_key] = periods[period] + EXPIRATION[period]
        cur_delta[cache_key] = 0
      end

      return current_metric or 0
    end
  }
}
