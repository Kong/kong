local singletons = require "kong.singletons"
local timestamp = require "kong.tools.timestamp"
local redis = require "resty.redis"
local policy_cluster = require "kong.plugins.rate-limiting.policies.cluster"
local reports = require "kong.reports"


local ngx_log = ngx.log
local shm = ngx.shared.kong_rate_limiting_counters
local pairs = pairs
local fmt = string.format


local NULL_UUID = "00000000-0000-0000-0000-000000000000"


local function is_present(str)
  return str and str ~= "" and str ~= ngx.null
end


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


local get_local_key = function(conf, identifier, period_date, name)
  local route_id, service_id, api_id = get_ids(conf)

  if api_id == NULL_UUID then
    return fmt("ratelimit:%s:%s:%s:%s:%s", route_id, service_id, identifier, period_date, name)
  end

  return fmt("ratelimit:%s:%s:%s:%s", api_id, identifier, period_date, name)
end


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
    increment = function(conf, limits, identifier, current_timestamp, value)
      local periods = timestamp.get_timestamps(current_timestamp)
      for period, period_date in pairs(periods) do
        if limits[period] then
          local cache_key = get_local_key(conf, identifier, period_date, period)
          local newval, err = shm:incr(cache_key, value, 0)
          if not newval then
            ngx_log(ngx.ERR, "[rate-limiting] could not increment counter ",
                             "for period '", period, "': ", err)
            return nil, err
          end
        end
      end

      return true
    end,
    usage = function(conf, identifier, current_timestamp, name)
      local periods = timestamp.get_timestamps(current_timestamp)
      local cache_key = get_local_key(conf, identifier, periods[name], name)
      local current_metric, err = shm:get(cache_key)
      if err then
        return nil, err
      end
      return current_metric and current_metric or 0
    end
  },
  ["cluster"] = {
    increment = function(conf, limits, identifier, current_timestamp, value)
      local db = singletons.dao.db
      local route_id, service_id, api_id = get_ids(conf)

      local ok, err

      if api_id == NULL_UUID then
        ok, err = policy_cluster[db.name].increment(db, limits, route_id, service_id,
                                                    identifier, current_timestamp, value)

      else
        ok, err = policy_cluster[db.name].increment_api(db, limits, api_id, identifier,
                                                        current_timestamp, value)
      end

      if not ok then
        ngx_log(ngx.ERR, "[rate-limiting] cluster policy: could not increment ",
                          db.name, " counter: ", err)
      end

      return ok, err
    end,
    usage = function(conf, identifier, current_timestamp, name)
      local db = singletons.dao.db
      local route_id, service_id, api_id = get_ids(conf)
      local row, err

      if api_id == NULL_UUID then
        row, err = policy_cluster[db.name].find(db, route_id, service_id,
                                                identifier, current_timestamp, name)
      else
        row, err = policy_cluster[db.name].find_api(db, api_id, identifier,
                                                    current_timestamp, name)
      end

      if err then
        return nil, err
      end

      return row and row.value or 0
    end
  },
  ["redis"] = {
    increment = function(conf, limits, identifier, current_timestamp, value)
      local red = redis:new()
      red:set_timeout(conf.redis_timeout)
      local ok, err = red:connect(conf.redis_host, conf.redis_port)
      if not ok then
        ngx_log(ngx.ERR, "failed to connect to Redis: ", err)
        return nil, err
      end

      local times, err = red:get_reused_times()
      if err then
        ngx_log(ngx.ERR, "failed to get connect reused times: ", err)
        return nil, err
      end

      if times == 0 and is_present(conf.redis_password) then
        local ok, err = red:auth(conf.redis_password)
        if not ok then
          ngx_log(ngx.ERR, "failed to auth Redis: ", err)
          return nil, err
        end
      end

      if times ~= 0 or conf.redis_database then
        -- The connection pool is shared between multiple instances of this
        -- plugin, and instances of the response-ratelimiting plugin.
        -- Because there isn't a way for us to know which Redis database a given
        -- socket is connected to without a roundtrip, we force the retrieved
        -- socket to select the desired database.
        -- When the connection is fresh and the database is the default one, we
        -- can skip this roundtrip.

        local ok, err = red:select(conf.redis_database or 0)
        if not ok then
          ngx_log(ngx.ERR, "failed to change Redis database: ", err)
          return nil, err
        end
      end

      local keys = {}
      local expirations = {}
      local idx = 0
      local periods = timestamp.get_timestamps(current_timestamp)
      for period, period_date in pairs(periods) do
        if limits[period] then
          local cache_key = get_local_key(conf, identifier, period_date, period)
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
    usage = function(conf, identifier, current_timestamp, name)
      local red = redis:new()
      red:set_timeout(conf.redis_timeout)
      local ok, err = red:connect(conf.redis_host, conf.redis_port)
      if not ok then
        ngx_log(ngx.ERR, "failed to connect to Redis: ", err)
        return nil, err
      end

      local times, err = red:get_reused_times()
      if err then
        ngx_log(ngx.ERR, "failed to get connect reused times: ", err)
        return nil, err
      end

      if times == 0 and is_present(conf.redis_password) then
        local ok, err = red:auth(conf.redis_password)
        if not ok then
          ngx_log(ngx.ERR, "failed to connect to Redis: ", err)
          return nil, err
        end
      end

      if times ~= 0 or conf.redis_database then
        -- The connection pool is shared between multiple instances of this
        -- plugin, and instances of the response-ratelimiting plugin.
        -- Because there isn't a way for us to know which Redis database a given
        -- socket is connected to without a roundtrip, we force the retrieved
        -- socket to select the desired database.
        -- When the connection is fresh and the database is the default one, we
        -- can skip this roundtrip.

        local ok, err = red:select(conf.redis_database or 0)
        if not ok then
          ngx_log(ngx.ERR, "failed to change Redis database: ", err)
          return nil, err
        end
      end

      reports.retrieve_redis_version(red)

      local periods = timestamp.get_timestamps(current_timestamp)
      local cache_key = get_local_key(conf, identifier, periods[name], name)
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
