local singletons = require "kong.singletons"
local timestamp = require "kong.tools.timestamp"
local redis = require "resty.redis"
local policy_cluster = require "kong.plugins.response-ratelimiting.policies.cluster"
local reports = require "kong.core.reports"


local ngx_log = ngx.log
local shm = ngx.shared.kong_rate_limiting_counters or ngx.shared.kong_cache
local pairs = pairs
local fmt = string.format


local NULL_UUID = "00000000-0000-0000-0000-000000000000"


local function get_ids(conf)
  conf = conf or {}

  local api_id = conf.api_id

  if api_id and api_id ~= ngx.null then
    return nil, nil, api_id
  end

  api_id = NULL_UUID

  local route_id   = conf.route_id
  local service_id = conf.service_id

  if not route_id or route_id == ngx.null then
    route_id = NULL_UUID
  end

  if not service_id or service_id == ngx.null then
    service_id = NULL_UUID
  end

  return route_id, service_id, api_id
end


local get_local_key = function(conf, identifier, period_date, name, period)
  local route_id, service_id, api_id = get_ids(conf)

  if api_id == NULL_UUID then
    return fmt("response-ratelimit:%s:%s:%s:%s:%s:%s",
               route_id, service_id, identifier, period_date, name, period)
  end

  return fmt("response-ratelimit:%s:%s:%s:%s:%s", api_id, identifier, period_date, name, period)
end


local sock_opts = {}


local EXPIRATIONS = {
  second = 1,
  minute = 60,
  hour = 3600,
  day = 86400,
  month = 2592000,
  year = 31536000,
}

return {
  ["local"] = {
    increment = function(conf, identifier, current_timestamp, value, name)
      local periods = timestamp.get_timestamps(current_timestamp)
      for period, period_date in pairs(periods) do
        local cache_key = get_local_key(conf, identifier, period_date, name, period)

        local newval, err = shm:incr(cache_key, value, 0)
        if not newval then
          ngx_log(ngx.ERR, "[response-ratelimiting] could not increment counter ",
                           "for period '", period, "': ", err)
          return nil, err
        end
      end

      return true
    end,
    usage = function(conf, identifier, current_timestamp, period, name)
      local periods = timestamp.get_timestamps(current_timestamp)
      local cache_key = get_local_key(conf, identifier, periods[period], name, period)
      local current_metric, err = shm:get(cache_key)
      if err then
        return nil, err
      end
      return current_metric and current_metric or 0
    end
  },
  ["cluster"] = {
    increment = function(conf, identifier, current_timestamp, value, name)
      local db = singletons.dao.db
      local route_id, service_id, api_id = get_ids(conf)

      local ok, err

      if api_id == NULL_UUID then
        ok, err = policy_cluster[db.name].increment(db, route_id, service_id, identifier,
                                                    current_timestamp, value, name)

      else
        ok, err = policy_cluster[db.name].increment_api(db, api_id, identifier,
                                                        current_timestamp, value, name)
      end

      if not ok then
        ngx_log(ngx.ERR, "[response-ratelimiting] cluster policy: could not increment ",
                          db.name, " counter: ", err)
      end

      return ok, err
    end,
    usage = function(conf, identifier, current_timestamp, period, name)
      local db = singletons.dao.db
      local route_id, service_id, api_id = get_ids(conf)

      local rows, err

      if api_id == NULL_UUID then
        rows, err = policy_cluster[db.name].find(db, route_id, service_id, identifier,
                                                 current_timestamp, period, name)

      else
        rows, err = policy_cluster[db.name].find_api(db, api_id, identifier,
                                                     current_timestamp, period, name)
      end

      if err then
        return nil, err
      end

      return rows and rows.value or 0
    end
  },
  ["redis"] = {
    increment = function(conf, identifier, current_timestamp, value, name)
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
        ngx_log(ngx.ERR, "failed to connect to Redis: ", err)
        return nil, err
      end

      local times, err = red:get_reused_times()
      if err then
        ngx_log(ngx.ERR, "failed to get connect reused times: ", err)
        return nil, err
      end

      if times == 0 then
        if conf.redis_password and conf.redis_password ~= "" then
          local ok, err = red:auth(conf.redis_password)
          if not ok then
            ngx_log(ngx.ERR, "failed to auth Redis: ", err)
            return nil, err
          end
        end

        if conf.redis_database ~= 0 then
          -- Only call select first time, since we know the connection is shared
          -- between instances that use the same redis database

          local ok, err = red:select(conf.redis_database)
          if not ok then
            ngx_log(ngx.ERR, "failed to change Redis database: ", err)
            return nil, err
          end
        end
      end

      local keys = {}
      local expirations = {}
      local idx = 0
      local periods = timestamp.get_timestamps(current_timestamp)
      for period, period_date in pairs(periods) do
        local cache_key = get_local_key(conf, identifier, period_date, name, period)
        local exists, err = red:exists(cache_key)
        if err then
          ngx_log(ngx.ERR, "failed to query Redis: ", err)
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
        ngx_log(ngx.ERR, "failed to commit pipeline in Redis: ", err)
        return nil, err
      end
      local ok, err = red:set_keepalive(10000, 100)
      if not ok then
        ngx_log(ngx.ERR, "failed to set Redis keepalive: ", err)
        return nil, err
      end

      return true
    end,
    usage = function(conf, identifier, current_timestamp, period, name)
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
        ngx_log(ngx.ERR, "failed to connect to Redis: ", err)
        return nil, err
      end

      local times, err = red:get_reused_times()
      if err then
        ngx_log(ngx.ERR, "failed to get connect reused times: ", err)
        return nil, err
      end

      if times == 0 then
        if conf.redis_password and conf.redis_password ~= "" then
          local ok, err = red:auth(conf.redis_password)
          if not ok then
            ngx_log(ngx.ERR, "failed to auth Redis: ", err)
            return nil, err
          end
        end

        if conf.redis_database ~= 0 then
          -- Only call select first time, since we know the connection is shared
          -- between instances that use the same redis database

          local ok, err = red:select(conf.redis_database)
          if not ok then
            ngx_log(ngx.ERR, "failed to change Redis database: ", err)
            return nil, err
          end
        end
      end

      reports.retrieve_redis_version(red)

      local periods = timestamp.get_timestamps(current_timestamp)
      local cache_key = get_local_key(conf, identifier, periods[period], name, period)
      local current_metric, err = red:get(cache_key)
      if err then
        return nil, err
      end

      if current_metric == ngx.null then
        current_metric = nil
      end

      local ok, err = red:set_keepalive(10000, 100)
      if not ok then
        ngx_log(ngx.ERR, "failed to set Redis keepalive: ", err)
      end

      return current_metric or 0
    end
  }
}
