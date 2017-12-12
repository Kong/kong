local timestamp = require "kong.tools.timestamp"
-- TODO add this to dependency BLOCKER (need to publish https://github.com/steve0511/resty-redis-cluster on luarocks)
local redis_cluster = require "rediscluster" 
local ngx_log = ngx.log
local pairs = pairs

-- TODO duplicate logic between redis single node and cluster; 
local get_local_key = function(api_id, identifier, period_date, name)
  return string.format("redis-ratelimit:%s:%s:%s:%s", api_id, identifier, period_date, name)
end

local EXPIRATIONS = {
  second = 1,
  minute = 60,
  hour = 3600,
  day = 86400,
  month = 2592000,
  year = 31536000,
}

local servers_cache = {}
local servers_cache_init = false

-- generate configuration for rediscluster from the conf(conf is from the configuration of the plugin)
local rc_config_from_conf = function(conf)
  local rc_config = {}
  rc_config.name = conf.redis_cluster_name

  -- TODO add override: if configuration is specified in plugin then use that
  -- if cache hit then set and return
  if servers_cache_init then
    rc_config.serv_list = servers_cache
    return rc_config
  end

local hosts_string = os.getenv("KONG_REDIS_CLUSTER_HOSTS")
local ports_string = os.getenv("KONG_REDIS_CLUSTER_PORTS")
if not hosts_string or not ports_string then
    return nil, error("Enviornment variables for redis configuration are not set.")
end
local i = 0
for host in string.gmatch(hosts_string, '([^,]+)') do
    i = i+1
    conf.redis_hosts[i] = host
end
i = 0
for port in string.gmatch(ports_string, '([^,]+)') do
    i = i+1
    conf.redis_ports[i] = port
end
  --add redis nodes
  local servers = {}
  local count = 1
  for index, _ in pairs(conf.redis_hosts) do
			servers[#servers + 1 ] = {ip = conf.redis_hosts[count], port = conf.redis_ports[count] }
      count = count + 1
  end 
  -- set cache 
  servers_cache = servers
  servers_cache_init = true
  rc_config.serv_list = servers
  rc_config.connection_timout = conf.redis_timeout
  return rc_config
end

return {
  increment = function(conf, limits, api_id, identifier, current_timestamp, value)

    local rc_conf, err = rc_config_from_conf(conf)
    if err then
      return nil, err
    end

    local redis_cluster, err = redis_cluster:new(rc_conf)
    if err then
      ngx_log(ngx.ERR,"Failed to instantiate a rediscluster")
      return nil, err
    end

    local periods = timestamp.get_timestamps(current_timestamp)

    for period, period_date in pairs(periods) do
      if limits[period] then
        local cache_key = get_local_key(api_id, identifier, period_date, period)
        local exists, err = redis_cluster:exists(cache_key)
        if err then
          ngx_log(ngx.ERR, "failed to query Redis: ", err)
          return nil, err
        end
        --TODO(Harry) pull the single pipeline fix from master here
        redis_cluster:init_pipeline()
        redis_cluster:incrby(cache_key, value)
        if not exists or exists == 0 then
          redis_cluster:expire(cache_key, EXPIRATIONS[period])
        end

        local _, err = redis_cluster:commit_pipeline()
        
        if err then
          ngx_log(ngx.ERR, "failed to commit pipeline in Redis: ", err)
          return nil, err
        end
      end
    end
    return true
  end,

  usage = function(conf, api_id, identifier, current_timestamp, name)
    local rc_conf,err = rc_config_from_conf(conf)

    if err then
      return nil, err
    end

    local redis_cluster, err = redis_cluster:new(rc_conf)

    if err then
      ngx_log(ngx.ERR,"Failed to instantiate a rediscluster")
      return nil, err
    end

    local periods = timestamp.get_timestamps(current_timestamp)
    local cache_key = get_local_key(api_id, identifier, periods[name], name)
    local current_metric, err = redis_cluster:get(cache_key)

    if err then
      return nil, err
    end

    if current_metric == ngx.null then
      current_metric = nil
    end

    return current_metric or 0
  end
}