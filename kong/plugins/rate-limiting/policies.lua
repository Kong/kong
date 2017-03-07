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
  year = 31536000,
}

return {
  ["local"] = {
    increment = function(conf, api_id, identifier, current_timestamp, value)
      local periods = timestamp.get_timestamps(current_timestamp)
      for period, period_date in pairs(periods) do
        local cache_key = get_local_key(api_id, identifier, period_date, period)
        cache.rawadd(cache_key, 0, EXPIRATIONS[period])

        local _, err = cache.incr(cache_key, value)
        if err then
          ngx_log("[rate-limiting] could not increment counter for period '"..period.."': "..tostring(err))
          return nil, err
        end
      end

      return true
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
      for period, period_date in pairs(periods) do
        local cache_key = get_local_key(api_id, identifier, period_date, period)
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
    usage = function(conf, api_id, identifier, current_timestamp, name)
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
  },
  ["distributed"] = {
    increment = function(conf, api_id, identifier, current_timestamp, increment)
      local periods = timestamp.get_timestamps(current_timestamp)
      -- increment in cache
      for period, period_date in pairs(periods) do
        local cache_key = get_local_key(api_id, identifier, period_date, period)
        local counter_key = cache_key.."counter"
        -- TODO: fix race condition with cache.rawget_or_rawset() from
        -- https://github.com/Mashape/kong/pull/2100
        if not cache.rawget(cache_key) then
          cache.rawset(cache_key, 0, EXPIRATIONS[period])
          cache.rawset(counter_key, 0, EXPIRATIONS[period])
        end

        local _, err = cache.incr(cache_key, increment)
        if err then
          ngx_log("[rate-limiting] could not increment counter for period '"
          ..period.."': "..tostring(err))
          return nil, err
        end
      end

      -- when was last resync ?
      local resync_key = "last_resync:"..api_id..":"..identifier
      local last_resync = cache.rawget(resync_key)
      -- first init
      if not last_resync then
        last_resync = current_timestamp
        cache.rawset(resync_key, last_resync)
      end

      -- check expiration
      local diff = current_timestamp - last_resync
      -- TODO : make db usage sync frequency a parameter
      if diff > 30000 then
        for period, period_date in pairs(periods) do
          local cache_key = get_local_key(api_id, identifier, period_date, period)
          local counter_key = cache_key.."counter"
          local m = cache.rawget(cache_key)
          if m then
            local c = cache.rawget(counter_key)
            -- calculate difference
            local d = m - c
            local _, stmt_err = singletons.dao.ratelimiting_metrics:update(api_id, identifier, period_date, period, d)
            if stmt_err then
              ngx.log(ngx.ERR, "failed to increment: ", tostring(stmt_err))
            end
          end
        end
        cache.rawset(resync_key, current_timestamp)
      end
    end,

    usage = function(conf, api_id, identifier, current_timestamp, period)
      -- Refresh the number of members in the cluster
      local function refresh_members(current_timestamp)
          -- Is the cluster size (in cache) to be refreshed ?
          local members_resync = cache.rawget("members_resync")
          -- first init
          if not members_resync then
              members_resync = current_timestamp
              cache.rawset("members_resync", members_resync)
          end

          local diff = current_timestamp - members_resync

          local nb_members = cache.rawget("nb_members")
          -- first init or resync
          if (not nb_members or diff > 30000) then
              local members, serf_err = singletons.serf:members()
              if serf_err then
                  ngx.log(ngx.ERR, "failed to get members: ", tostring(err))
                  return responses.send(500, "Could not determine cluster size")
              end
              nb_members = 0
              local member_names = {}
              for k,v in pairs(members) do
                  if (v.status=="alive") then
                      nb_members = nb_members + 1
                  end
              end
              cache.rawset("nb_members", nb_members)
              cache.rawset("members_resync", current_timestamp)
          end
          return nb_members
      end

      local nb_members = refresh_members(current_timestamp)
      local periods = timestamp.get_timestamps(current_timestamp)
      local cache_key = get_local_key(api_id, identifier, periods[period], period)
      local counter_key = cache_key.."counter"
      local current_metric = cache.rawget(cache_key)

      -- first init or after db resync
      if not current_metric then
          local cm, err = singletons.dao.ratelimiting_metrics:find(api_id, identifier, periods[period], period)
          if err then
              return nil, err
          end
          current_metric = cm and cm.value or 0
          current_metric = current_metric / nb_members
          cache.rawset(cache_key, current_metric, EXPIRATIONS[period])
          cache.rawset(counter_key, current_metric, EXPIRATIONS[period])
      end

      local current_usage = current_metric and current_metric or 0
      local cluster_usage = current_usage * nb_members

      return cluster_usage
    end
  }
}
