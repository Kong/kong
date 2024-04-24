local set_log_level                = require("resty.kong.log").set_log_level
local cjson                        = require("cjson.safe")
local constants                    = require("kong.constants")

local LOG_LEVELS                   = constants.LOG_LEVELS
local DYN_LOG_LEVEL_KEY            = constants.DYN_LOG_LEVEL_KEY
local DYN_LOG_LEVEL_TIMEOUT_AT_KEY = constants.DYN_LOG_LEVEL_TIMEOUT_AT_KEY

local ngx                          = ngx
local kong                         = kong
local pcall                        = pcall
local type                         = type
local tostring                     = tostring
local tonumber                     = tonumber

local get_log_level                = require("resty.kong.log").get_log_level

local NODE_LEVEL_BROADCAST         = false
local CLUSTER_LEVEL_BROADCAST      = true
local DEFAULT_LOG_LEVEL_TIMEOUT    = 60 -- 60s


local function handle_put_log_level(self, broadcast)
  if kong.configuration.database == "off" then
    local message = "cannot change log level when not using a database"
    return kong.response.exit(405, { message = message })
  end

  local log_level = LOG_LEVELS[self.params.log_level]
  local timeout = math.ceil(tonumber(self.params.timeout) or DEFAULT_LOG_LEVEL_TIMEOUT)

  if type(log_level) ~= "number" then
    return kong.response.exit(400, { message = "unknown log level: " .. self.params.log_level })
  end

  if timeout < 0 then
    return kong.response.exit(400, { message = "timeout must be greater than or equal to 0" })
  end

  local cur_log_level = get_log_level()

  if cur_log_level == log_level then
    local message = "log level is already " .. self.params.log_level
    return kong.response.exit(200, { message = message })
  end

  local ok, err = pcall(set_log_level, log_level, timeout)

  if not ok then
    local message = "failed setting log level: " .. err
    return kong.response.exit(500, { message = message })
  end

  local data = {
    log_level = log_level,
    timeout = timeout,
  }

  -- broadcast to all workers in a node
  ok, err = kong.worker_events.post("debug", "log_level", data)

  if not ok then
    local message = "failed broadcasting to workers: " .. err
    return kong.response.exit(500, { message = message })
  end

  if broadcast then
    -- broadcast to all nodes in a cluster
    ok, err = kong.cluster_events:broadcast("log_level", cjson.encode(data))

    if not ok then
      local message = "failed broadcasting to cluster: " .. err
      return kong.response.exit(500, { message = message })
    end
  end

  -- store in shm so that newly spawned workers can update their log levels
  ok, err = ngx.shared.kong:set(DYN_LOG_LEVEL_KEY, log_level, timeout)

  if not ok then
    local message = "failed storing log level in shm: " .. err
    return kong.response.exit(500, { message = message })
  end

  ok, err = ngx.shared.kong:set(DYN_LOG_LEVEL_TIMEOUT_AT_KEY, ngx.time() + timeout, timeout)

  if not ok then
    local message = "failed storing the timeout of log level in shm: " .. err
    return kong.response.exit(500, { message = message })
  end

  return kong.response.exit(200, { message = "log level changed" })
end


local routes = {
  ["/debug/node/log-level"] = {
    GET = function(self)
      local cur_level = get_log_level()

      if type(LOG_LEVELS[cur_level]) ~= "string" then
        local message = "unknown log level: " .. tostring(cur_level)
        return kong.response.exit(500, { message = message })
      end

      return kong.response.exit(200, { message = "log level: " .. LOG_LEVELS[cur_level] })
    end,
  },
  ["/debug/node/log-level/:log_level"] = {
    PUT = function(self)
      return handle_put_log_level(self, NODE_LEVEL_BROADCAST)
    end
  },
}


local cluster_name

if kong.configuration.role == "control_plane" then
  cluster_name = "/debug/cluster/control-planes-nodes/log-level/:log_level"
else
  cluster_name = "/debug/cluster/log-level/:log_level"
end

routes[cluster_name] = {
  PUT = function(self)
    return handle_put_log_level(self, CLUSTER_LEVEL_BROADCAST)
  end
}


if kong.rpc then
  routes["/clustering/data-planes/:node_id/log-level"] = {
    GET = function(self)
      local res, err =
        kong.rpc:call(self.params.node_id, "kong.debug.log_level.v1.get_log_level")
      if not res then
        return kong.response.exit(500, { message = err, })
      end

      return kong.response.exit(200, res)
    end,
    PUT = function(self)
      local new_level = self.params.current_level
      local timeout = self.params.timeout and
                      math.ceil(tonumber(self.params.timeout)) or nil

      if not new_level then
        return kong.response.exit(400, { message = "Required parameter \"current_level\" is missing.", })
      end

      local res, err = kong.rpc:call(self.params.node_id,
                                     "kong.debug.log_level.v1.set_log_level",
                                     new_level,
                                     timeout)
      if not res then
        return kong.response.exit(500, { message = err, })
      end

      return kong.response.exit(201)
    end,
    DELETE = function(self)
      local res, err = kong.rpc:call(self.params.node_id,
                                     "kong.debug.log_level.v1.set_log_level",
                                     "warn",
                                     0)
      if not res then
        return kong.response.exit(500, { message = err, })
      end

      return kong.response.exit(204)
    end,
  }
end

return routes
