local singletons = require "kong.singletons"
local timestamp = require "kong.tools.timestamp"
local cache = require "kong.tools.database_cache"
local redis = require "resty.redis"
local ngx_log = ngx.log

local pairs = pairs
local fmt = string.format

local get_local_key = function(api_id, identifier, period_date, name)
  return fmt("ratelimit:%s:%s:%s:%s", api_id, identifier, period_date, name)
end

local EXPIRATIONS = {
  second = 1,
  minute = 60,
  hour = 3600,
  day = 86400,
  month = 2592000,
  year = 31104000
}

return {
  ["local"] = {
    increment = function(conf, api_id, identifier, current_timestamp, value)
      local periods = timestamp.get_timestamps(current_timestamp)
      for period, period_date in pairs(periods) do
        local cache_key = get_local_key(api_id, identifier, period_date, period)
        if not cache.rawget(cache_key) then
          cache.rawset(cache_key, 0, EXPIRATIONS[period])
        end

        local _, err = cache.incr(cache_key, value)
        if err then
          ngx_log("[rate-limiting] could not increment counter for period '"..period.."': "..tostring(err))
        end
      end
    end,
    usage = function(conf, api_id, identifier, current_timestamp, name)
      local periods = timestamp.get_timestamps(current_timestamp)
      local cache_key = get_local_key(api_id, identifier, periods[name], name)
      local current_metric, err = cache.rawget(cache_key)
      if err then
        return nil, err
      end
      return current_metric and current_metric or 0
    end
  },
  ["cluster"] = {
    increment = function(conf, api_id, identifier, current_timestamp, value)
      local _, stmt_err = singletons.dao.ratelimiting_metrics:increment(api_id, identifier, current_timestamp, value)
      if stmt_err then
        ngx_log(ngx.ERR, "failed to increment: ", tostring(stmt_err))
      end
    end,
    usage = function(conf, api_id, identifier, current_timestamp, name)
      local current_metric, err = singletons.dao.ratelimiting_metrics:find(api_id, identifier, current_timestamp, name)
      if err then
        return nil, err
      end
      return current_metric and current_metric.value or 0
    end
  },
  ["redis"] = {
    increment = function(conf, api_id, identifier, current_timestamp, value)
      local red = redis:new()
      red:set_timeout(conf.redis_timeout)
      local ok, err = red:connect(conf.redis_host, conf.redis_port)
      if not ok then
        ngx_log(ngx.ERR, "failed to connect to Redis: ", err)
        return
      end

      if conf.redis_password and conf.redis_password ~= "" then
        local ok, err = red:auth(conf.redis_password)
        if not ok then
          ngx_log(ngx.ERR, "failed to connect to Redis: ", err)
          return
        end
      end

      local periods = timestamp.get_timestamps(current_timestamp)
      for period, period_date in pairs(periods) do
        local cache_key = get_local_key(api_id, identifier, period_date, period)
        local exists, err = red:exists(cache_key)
        if err then
          ngx_log(ngx.ERR, "failed to query Redis: ", err)
          return
        end

        red:init_pipeline((not exists or exists == 0) and 2 or 1)
        red:incrby(cache_key, value)
        if not exists or exists == 0 then
          red:expire(cache_key, EXPIRATIONS[period])
        end

        local _, err = red:commit_pipeline()
        if err then
          ngx_log(ngx.ERR, "failed to commit pipeline in Redis: ", err)
          return
        end
      end

      local ok, err = red:set_keepalive(10000, 100)
      if not ok then
        ngx_log(ngx.ERR, "failed to set Redis keepalive: ", err)
        return
      end
    end,
    usage = function(conf, api_id, identifier, current_timestamp, name)
      local red = redis:new()
      red:set_timeout(conf.redis_timeout)
      local ok, err = red:connect(conf.redis_host, conf.redis_port)
      if not ok then
        ngx_log(ngx.ERR, "failed to connect to Redis: ", err)
        return
      end

      if conf.redis_password and conf.redis_password ~= "" then
        local ok, err = red:auth(conf.redis_password)
        if not ok then
          ngx_log(ngx.ERR, "failed to connect to Redis: ", err)
          return
        end
      end

      local periods = timestamp.get_timestamps(current_timestamp)
      local cache_key = get_local_key(api_id, identifier, periods[name], name)
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
