local timestamp = require "kong.tools.timestamp"
local redis = require "resty.redis"
local policy_cluster = require "kong.plugins.response-ratelimiting.policies.cluster"
local reports = require "kong.reports"


local kong = kong
local null = ngx.null
local shm = ngx.shared.kong_rate_limiting_counters
local pairs = pairs
local fmt = string.format


local EMPTY_UUID = "00000000-0000-0000-0000-000000000000"
local EXPIRATIONS = {
  second = 1,
  minute = 60,
  hour = 3600,
  day = 86400,
  month = 2592000,
  year = 31536000,
}

local function is_present(str)
  return str and str ~= "" and str ~= null
end


local function get_service_and_route_ids(conf)
  conf = conf or {}

  local service_id = conf.service_id
  if not service_id or service_id == null then
    service_id = EMPTY_UUID
  end

  local route_id   = conf.route_id
  if not route_id or route_id == null then
    route_id = EMPTY_UUID
  end

  return service_id, route_id
end


local get_local_key = function(conf, identifier, name, period, period_date)
  local service_id, route_id = get_service_and_route_ids(conf)
  return fmt("response-ratelimit:%s:%s:%s:%s:%s:%s",
             route_id, service_id, identifier, period_date, name, period)
end


local sock_opts = {}
local function get_redis_connection(conf)
  local red = redis:new()
  red:set_timeout(conf.redis_timeout)

  -- use a special pool name only if redis_database is set to non-zero
  -- otherwise use the default pool name host:port
  sock_opts.pool = conf.redis_database and
                   conf.redis_host .. ":" .. conf.redis_port ..
                   ":" .. conf.redis_database
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
        ok, err = red:auth(conf.redis_username, conf.redis_password)
      else
        ok, err = red:auth(conf.redis_password)
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


return {
  ["local"] = {
    increment = function(conf, identifier, name, current_timestamp, value)
      local periods = timestamp.get_timestamps(current_timestamp)
      for period, period_date in pairs(periods) do
        local cache_key = get_local_key(conf, identifier, name, period,
                                        period_date)

        local newval, err = shm:incr(cache_key, value, 0)
        if not newval then
          kong.log.err("could not increment counter for period '",
                       period, "': ", err)
          return nil, err
        end
      end

      return true
    end,
    usage = function(conf, identifier, name, period, current_timestamp)
      local periods = timestamp.get_timestamps(current_timestamp)
      local cache_key = get_local_key(conf, identifier, name, period, periods[period])

      local current_metric, err = shm:get(cache_key)
      if err then
        return nil, err
      end

      return current_metric and current_metric or 0
    end
  },
  ["cluster"] = {
    increment = function(conf, identifier, name, current_timestamp, value)
      local db = kong.db
      local service_id, route_id = get_service_and_route_ids(conf)
      local policy = policy_cluster[db.strategy]

      local ok, err = policy.increment(db.connector, identifier, name,
                                       current_timestamp, service_id, route_id,
                                       value)

      if not ok then
        kong.log.err("cluster policy: could not increment ", db.strategy,
                     " counter: ", err)
      end

      return ok, err
    end,
    usage = function(conf, identifier, name, period, current_timestamp)
      local db = kong.db
      local service_id, route_id = get_service_and_route_ids(conf)
      local policy = policy_cluster[db.strategy]

      local row, err = policy.find(db.connector, identifier, name, period,
                                    current_timestamp, service_id, route_id)

      if err then
        return nil, err
      end

      if row and row.value ~= null and row.value > 0 then
        return row.value
      end

      return 0
    end
  },
  ["redis"] = {
    increment = function(conf, identifier, name, current_timestamp, value)
      local red, err = get_redis_connection(conf)
      if not red then
        return nil, err
      end

      local keys = {}
      local expirations = {}
      local idx = 0
      local periods = timestamp.get_timestamps(current_timestamp)
      for period, period_date in pairs(periods) do
        local cache_key = get_local_key(conf, identifier, name, period, period_date)
        local exists, err = red:exists(cache_key)
        if err then
          kong.log.err("failed to query Redis: ", err)
          return nil, err
        end

        idx = idx + 1
        keys[idx] = cache_key
        if not exists or exists == 0 then
          expirations[idx] = EXPIRATIONS[period]
        end
      end

      red:init_pipeline()
      for i = 1, idx do
        red:incrby(keys[i], value)
        if expirations[i] then
          red:expire(keys[i], expirations[i])
        end
      end

      local _, err = red:commit_pipeline()
      if err then
        kong.log.err("failed to commit pipeline in Redis: ", err)
        return nil, err
      end

      local ok, err = red:set_keepalive(10000, 100)
      if not ok then
        kong.log.err("failed to set Redis keepalive: ", err)
        return nil, err
      end

      return true
    end,
    usage = function(conf, identifier, name, period, current_timestamp)
      local red, err = get_redis_connection(conf)
      if not red then
        return nil, err
      end

      reports.retrieve_redis_version(red)

      local periods = timestamp.get_timestamps(current_timestamp)
      local cache_key = get_local_key(conf, identifier, name, period, periods[period])
      local current_metric, err = red:get(cache_key)
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

      return current_metric or 0
    end
  }
}
