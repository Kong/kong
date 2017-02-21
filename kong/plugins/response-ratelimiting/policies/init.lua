local singletons = require "kong.singletons"
local timestamp = require "kong.tools.timestamp"
local cache = require "kong.tools.database_cache"
local redis = require "resty.redis"
local policy_cluster = require "kong.plugins.response-ratelimiting.policies.cluster"
local ngx_log = ngx.log

local pairs = pairs
local fmt = string.format

local get_local_key = function(api_id, identifier, period_date, name, period)
  return fmt("response-ratelimit:%s:%s:%s:%s:%s", api_id, identifier, period_date, name, period)
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
    increment = function(conf, api_id, identifier, current_timestamp, value, name)
      local periods = timestamp.get_timestamps(current_timestamp)
      for period, period_date in pairs(periods) do
        local cache_key = get_local_key(api_id, identifier, period_date, name, period)
        if not cache.sh_get(cache_key) then
          cache.sh_set(cache_key, 0, EXPIRATIONS[period])
        end

        local _, err = cache.sh_incr(cache_key, value)
        if err then
          ngx_log("[response-ratelimiting] could not increment counter for period '"..period.."': "..tostring(err))
          return nil, err
        end
      end

      return true
    end,
    usage = function(conf, api_id, identifier, current_timestamp, period, name)
      local periods = timestamp.get_timestamps(current_timestamp)
      local cache_key = get_local_key(api_id, identifier, periods[period], name, period)
      local current_metric, err = cache.sh_get(cache_key)
      if err then
        return nil, err
      end
      return current_metric and current_metric or 0
    end
  },
  ["cluster"] = {
    increment = function(conf, api_id, identifier, current_timestamp, value, name)
      local db = singletons.dao.db
      local ok, err = policy_cluster[db.name].increment(db, api_id, identifier,
                                                        current_timestamp, value,
                                                        name)
      if not ok then
        ngx_log(ngx.ERR, "[response-ratelimiting] cluster policy: could not increment ",
                          db.name, " counter: ", err)
      end

      return ok, err
    end,
    usage = function(conf, api_id, identifier, current_timestamp, period, name)
      local db = singletons.dao.db
      local rows, err = policy_cluster[db.name].find(db, api_id, identifier,
                                                     current_timestamp, period,
                                                     name)
      if err then return nil, err end

      return rows and rows.value or 0
    end
  },
  ["redis"] = {
    increment = function(conf, api_id, identifier, current_timestamp, value, name)
      local red = redis:new()
      red:set_timeout(conf.redis_timeout)
      local ok, err = red:connect(conf.redis_host, conf.redis_port)
      if not ok then
        ngx_log(ngx.ERR, "failed to connect to Redis: ", err)
        return nil, err
      end

      if conf.redis_password and conf.redis_password ~= "" then
        local ok, err = red:auth(conf.redis_password)
        if not ok then
          ngx_log(ngx.ERR, "failed to connect to Redis: ", err)
          return nil, err
        end
      end

      if conf.redis_database ~= nil and conf.redis_database > 0 then
        local ok, err = red:select(conf.redis_database)
        if not ok then
          ngx_log(ngx.ERR, "failed to change Redis database: ", err)
          return nil, err
        end
      end

      local periods = timestamp.get_timestamps(current_timestamp)
      for period, period_date in pairs(periods) do
        local cache_key = get_local_key(api_id, identifier, period_date, name, period)
        local exists, err = red:exists(cache_key)
        if err then
          ngx_log(ngx.ERR, "failed to query Redis: ", err)
          return nil, err
        end

        red:init_pipeline((not exists or exists == 0) and 2 or 1)
        red:incrby(cache_key, value)
        if not exists or exists == 0 then
          red:expire(cache_key, EXPIRATIONS[period])
        end

        local _, err = red:commit_pipeline()
        if err then
          ngx_log(ngx.ERR, "failed to commit pipeline in Redis: ", err)
          return nil, err
        end
      end

      local ok, err = red:set_keepalive(10000, 100)
      if not ok then
        ngx_log(ngx.ERR, "failed to set Redis keepalive: ", err)
        return nil, err
      end

      return true
    end,
    usage = function(conf, api_id, identifier, current_timestamp, period, name)
      local red = redis:new()
      red:set_timeout(conf.redis_timeout)
      local ok, err = red:connect(conf.redis_host, conf.redis_port)
      if not ok then
        ngx_log(ngx.ERR, "failed to connect to Redis: ", err)
        return nil, err
      end

      if conf.redis_password and conf.redis_password ~= "" then
        local ok, err = red:auth(conf.redis_password)
        if not ok then
          ngx_log(ngx.ERR, "failed to connect to Redis: ", err)
          return nil, err
        end
      end

      local periods = timestamp.get_timestamps(current_timestamp)
      local cache_key = get_local_key(api_id, identifier, periods[period], name, period)
      local current_metric, err = red:get(cache_key)
      if err then
        return nil, err
      end

      if current_metric == ngx.null then
        current_metric = nil
      end

      return current_metric and current_metric or 0
    end
  }
}
