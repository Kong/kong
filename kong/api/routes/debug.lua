local get_sys_filter_level = require("ngx.errlog").get_sys_filter_level
local set_log_level = require("resty.kong.log").set_log_level

local LOG_LEVELS = require("kong.constants").LOG_LEVELS

local ngx = ngx
local kong = kong
local pcall = pcall
local type = type
local tostring = tostring

local NODE_LEVEL_BROADCAST = false
local CLUSTER_LEVEL_BROADCAST = true

local function handle_put_log_level(self, broadcast)
  if kong.configuration.database == "off" then
    local message = "cannot change log level when not using a database"
    return kong.response.exit(405, { message = message })
  end

  local log_level = LOG_LEVELS[self.params.log_level]

  if type(log_level) ~= "number" then
    return kong.response.exit(400, { message = "unknown log level: " .. self.params.log_level })
  end

  local sys_filter_level = get_sys_filter_level()

  if sys_filter_level == log_level then
    local message = "log level is already " .. self.params.log_level
    return kong.response.exit(200, { message = message })
  end

  local ok, err = pcall(set_log_level, log_level)

  if not ok then
    local message = "failed setting log level: " .. err
    return kong.response.exit(500, { message = message })
  end

  -- broadcast to all workers in a node
  ok, err = kong.worker_events.post("debug", "log_level", log_level)

  if not ok then
    local message = "failed broadcasting to workers: " .. err
    return kong.response.exit(500, { message = message })
  end

  if broadcast then
    -- broadcast to all nodes in a cluster
    ok, err = kong.cluster_events:broadcast("log_level", tostring(log_level))

    if not ok then
      local message = "failed broadcasting to cluster: " .. err
      return kong.response.exit(500, { message = message })
    end
  end

  -- store in shm so that newly spawned workers can update their log levels
  ok, err = ngx.shared.kong:set("kong:log_level", log_level)

  if not ok then
    local message = "failed storing log level in shm: " .. err
    return kong.response.exit(500, { message = message })
  end

  -- store in global _G table for timers pre-created by lua-resty-timer-ng
  -- KAG-457 - find a better way to make this work with lua-resty-timer-ng
  _G.log_level = log_level

  return kong.response.exit(200, { message = "log level changed" })
end

local routes = {
  ["/debug/node/log-level"] = {
    GET = function(self)
      local sys_filter_level = get_sys_filter_level()
      local cur_level = LOG_LEVELS[sys_filter_level]

      if type(cur_level) ~= "string" then
        local message = "unknown log level: " .. tostring(sys_filter_level)
        return kong.response.exit(500, { message = message })
      end

      return kong.response.exit(200, { message = "log level: " .. cur_level })
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

return routes
