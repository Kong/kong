local Errors = require "kong.dao.errors"
local redis = require "resty.redis"

local REDIS = "redis"

return {
  fields = {
    second = { type = "number" },
    minute = { type = "number" },
    hour = { type = "number" },
    day = { type = "number" },
    month = { type = "number" },
    year = { type = "number" },
    limit_by = { type = "string", enum = {"consumer", "credential", "ip"}, default = "consumer" },
    policy = { type = "string", enum = {"local", "cluster", REDIS}, default = "cluster" },
    fault_tolerant = { type = "boolean", default = true },
    redis_host = { type = "string" },
    redis_port = { type = "number", default = 6379 },
    redis_password = { type = "string" },
    redis_timeout = { type = "number", default = 2000 },
    redis_database = { type = "number", default = 0 },
    hide_client_headers = { type = "boolean", default = false },
  },
  self_check = function(schema, plugin_t, dao, is_update)
    local ordered_periods = { "second", "minute", "hour", "day", "month", "year"}
    local has_value
    local invalid_order
    local invalid_value

    for i, v in ipairs(ordered_periods) do
      if plugin_t[v] then
        has_value = true
        if plugin_t[v] <=0 then
          invalid_value = "Value for " .. v .. " must be greater than zero"
        else
          for t = i+1, #ordered_periods do
            if plugin_t[ordered_periods[t]] and plugin_t[ordered_periods[t]] < plugin_t[v] then
              invalid_order = "The limit for " .. ordered_periods[t] .. " cannot be lower than the limit for " .. v
            end
          end
        end
      end
    end

    if not has_value then
      return false, Errors.schema "You need to set at least one limit: second, minute, hour, day, month, year"
    elseif invalid_value then
      return false, Errors.schema(invalid_value)
    elseif invalid_order then
      return false, Errors.schema(invalid_order)
    end

    if plugin_t.policy == REDIS then
      if not plugin_t.redis_host then
        return false, Errors.schema "You need to specify a Redis host"
      elseif not plugin_t.redis_port then
        return false, Errors.schema "You need to specify a Redis port"
      elseif not plugin_t.redis_timeout then
        return false, Errors.schema "You need to specify a Redis timeout"
      end
    end

    --Additional checks for redis-cluster configuration
    if plugin_t.policy == "redis-cluster" then

      if not (plugin_t.redis_database == 0) then
        return false, Errors.schema "Redis-cluster cannot have a database value"
      end

      -- TODO add check for configuration via plugin.conf
      -- if plugin configuration has hosts and ports then that takes precedence over env vars


		  -- read env vars and then set host:port arrays up for verfications
			local hosts_string = os.getenv("KONG_REDIS_CLUSTER_HOSTS")
			local ports_string = os.getenv("KONG_REDIS_CLUSTER_HOSTS")
			if not hosts_string or not ports_string then
				return nil, Errors.schema("Enviornment variables for redis configuration are not set.") 
			end
			local i = 0
			local hosts = {}
			local ports = {}
			for host in string.gmatch(hosts_string, '([^,]+)') do
				i = i+1
				hosts[i] = host
			end
			i = 0
			for port in string.gmatch(ports_string, '([^,]+)') do
				i = i+1
				ports[i] = port
			end
			local redis_hosts = hosts
			local redis_ports = ports
      local number_of_ports = 0
      local number_of_hosts = 0
      for count, value in pairs(redis_ports) do
        number_of_ports = number_of_ports + 1
      end
      for count, value in pairs(redis_hosts) do
        number_of_hosts = number_of_hosts + 1
      end
      if not (number_of_ports == number_of_hosts) then
        return false, Errors.schema(string.format("You need the same number of hosts(%s) and ports(%s) for your cluster",number_of_hosts,number_of_ports))
      end

      --TODO add a loop here to check every supplied host:port pair
      -- check if the nodes are in cluster mode or not
      -- TODO is DNS name supported here?
      local redis1 = redis:new()
      local _ , err = redis1:connect( redis_hosts[1], redis_ports[1])
      if err then
        return false, Errors.schema(string.format("Cannot connect to redis-node %s:%s is either not part of cluster or the cluster you gave is not working", plugin_t.redis_hosts[1], plugin_t.redis_ports[1] ))
      end
      -- Get the cluster configuration from the Cluster and verify it against the user's configuration.
      -- If don't match up, throw err
      local tableSlots = redis1:cluster("slots")
      if type(tableSlots) == "boolean" then
        return false, Errors.schema(string.format("Redis-node %s:%s has cluster mode disabled; this plugin connects to a redis cluster only", plugin_t.redis_hosts[1], plugin_t.redis_ports[1] ))
      end
    end
    
    return true
  end
}
