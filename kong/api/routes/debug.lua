-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local get_sys_filter_level            = require("ngx.errlog").get_sys_filter_level
local set_log_level                   = require("resty.kong.log").set_log_level

local LOG_LEVELS                      = require("kong.constants").LOG_LEVELS

local ngx                             = ngx
local kong                            = kong
local pcall                           = pcall
local type                            = type
local tostring                        = tostring
local string_format                   = string.format
local math_max                        = math.max
local math_random                     = math.random
local table_remove                    = table.remove

local ngx_time                        = ngx.time
local ngx_worker_pids                 = ngx.worker.pids -- luacheck: ignore
local ngx_worker_pid                  = ngx.worker.pid

local NODE_LEVEL_BROADCAST            = false
local CLUSTER_LEVEL_BROADCAST         = true

local MIN_PROFILING_TIMEOUT           = 10      -- seconds
local MAX_PROFILING_TIMEOUT           = 600     -- seconds

local DEFAULT_CPU_PROFILING_MODE      = "time"
local DEFAULT_CPU_PROFILING_STEP      = 250
local DEFAULT_CPU_PROFILING_INTERVAL  = 100     -- microseconds
local DEFAULT_CPU_PROFILING_TIMEOUT   = 60      -- seconds
local MIN_CPU_PROFILING_STEP          = 50
local MAX_CPU_PROFILING_STEP          = 1000
local MIN_CPU_PROFILING_INTERVAL      = 1       -- microseconds
local MAX_CPU_PROFILING_INTERVAL      = 1000000 -- microseconds

local DEFAULT_GC_SNAPSHOT_TIMEOUT     = 120     -- seconds

local ERR_MSG_INVALID_TIMEOUT         = string.format(
                                          "invalid timeout (must be between %d and %d): ",
                                          MIN_PROFILING_TIMEOUT, MAX_PROFILING_TIMEOUT
                                        )

local ERR_MSG_INVALID_STEP            = string.format(
                                          "invalid step (must be between %d and %d): ",
                                          MIN_CPU_PROFILING_STEP, MAX_CPU_PROFILING_STEP
                                        )

local ERR_MSG_INVALID_INTERVAL        = string.format(
                                          "invalid interval (must be between %d and %d): ",
                                          MIN_CPU_PROFILING_INTERVAL, MAX_CPU_PROFILING_INTERVAL
                                        )

local ERR_MSG_INVALID_MODE            = "invalid mode (must be 'time' or 'instruction'): "

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

  return kong.response.exit(200, { message = "log level changed" })
end

local function is_valid_worker_pid(pid)
  local pids = ngx_worker_pids()

  for _, p in ipairs(pids) do
    if p == pid then
      return true
    end
  end

  return false
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
  ["/debug/profiling/cpu"] = {
    GET = function(self)
      local state = kong.profiling.cpu.state()

      if state.status == "started" then
        state.remain = math_max(state.timeout_at - ngx_time(), 0)
        state.timeout_at = nil
      end

      return kong.response.exit(200, state)
    end,

    POST = function(self)
      local state = kong.profiling.cpu.state()

      if state.status == "started" then
        local resp_body = {
          status = "error",
          message = "profiling is already active at pid: " .. state.pid,
        }
        return kong.response.exit(409, resp_body)
      end

      local pid       = tonumber(self.params.pid)       or ngx_worker_pid()
      local mode      = self.params.mode                or DEFAULT_CPU_PROFILING_MODE
      local step      = tonumber(self.params.step)      or DEFAULT_CPU_PROFILING_STEP
      local interval  = tonumber(self.params.interval)  or DEFAULT_CPU_PROFILING_INTERVAL
      local timeout   = tonumber(self.params.timeout)   or DEFAULT_CPU_PROFILING_TIMEOUT

      if not is_valid_worker_pid(pid) then
        local resp_body = {
          status = "error",
          message = "invalid pid: " .. pid,
        }
        return kong.response.exit(400, resp_body)
      end

      if mode ~= "time" and mode ~= "instruction" then
        local resp_body = {
          status = "error",
          message = ERR_MSG_INVALID_MODE .. mode,
        }
        return kong.response.exit(400, resp_body)
      end

      if step < MIN_CPU_PROFILING_STEP or step > MAX_CPU_PROFILING_STEP then
        local resp_body = {
          status = "error",
          message = ERR_MSG_INVALID_STEP .. step,
        }
        return kong.response.exit(400, resp_body)
      end

      if interval < MIN_CPU_PROFILING_INTERVAL or interval > MAX_CPU_PROFILING_INTERVAL then
        local resp_body = {
          status = "error",
          message = ERR_MSG_INVALID_INTERVAL .. interval,
        }
        return kong.response.exit(400, resp_body)
      end

      if timeout < MIN_PROFILING_TIMEOUT or timeout > MAX_PROFILING_TIMEOUT then
        local resp_body = {
          status = "error",
          message = ERR_MSG_INVALID_TIMEOUT .. timeout,
        }
        return kong.response.exit(400, resp_body)
      end

      local path = string_format("%s/profiling/prof-%d-%d.cbt",
                                 kong.configuration.prefix, pid, ngx_time())

      local ok, err = kong.worker_events.post("profiling", "start", {
        pid = pid,
        mode = mode,
        step = step,
        interval = interval,
        path = path,
        timeout = timeout,
      })

      if not ok then
        local resp_body = {
          status = "error",
          message = "failed to post worker event: " .. err,
        }
        return kong.response.exit(500, resp_body)
      end

      local resp_body = {
        status = "started",
        message = "profiling is activated at pid: " .. pid,
      }
      return kong.response.exit(201, resp_body)
    end,

    DELETE = function(self)
      local state = kong.profiling.cpu.state()

      if state.status ~= "started" then
        local resp_body = {
          status = "error",
          message = "profiling is not active",
        }
        return kong.response.exit(400, resp_body)
      end

      local ok, err = kong.worker_events.post("profiling", "stop", { pid = tonumber(state.pid) })

      if not ok then
        local resp_body = {
          status = "error",
          message = "failed to post worker event: " .. err,
        }
        return kong.response.exit(500, resp_body)
      end

      return kong.response.exit(204)
    end,
  },
  ["/debug/profiling/gc-snapshot"] = {
    GET = function(self)
      local state = kong.profiling.gc_snapshot.state()

      if state.status == "started" then
        state.remain = math_max(state.timeout_at - ngx_time(), 0)
        state.timeout_at = nil
      end

      return kong.response.exit(200, state)
    end,
    POST = function(self)
      local state = kong.profiling.gc_snapshot.state()

      if state.status == "started" then
        local resp_body = {
          status = "error",
          message = "gc-snapshot is already active at pid: " .. state.pid,
        }
        return kong.response.exit(409, resp_body)
      end

      local pid     = tonumber(self.params.pid)     or ngx_worker_pid()
      local timeout = tonumber(self.params.timeout) or DEFAULT_GC_SNAPSHOT_TIMEOUT

      if timeout < MIN_PROFILING_TIMEOUT or timeout > MAX_PROFILING_TIMEOUT then
        local resp_body = {
          status = "error",
          message = ERR_MSG_INVALID_TIMEOUT .. timeout,
        }
        return kong.response.exit(400, resp_body)
      end

      if not is_valid_worker_pid(pid) then
        local resp_body = {
          status = "error",
          message = "invalid pid: " .. pid,
        }
        return kong.response.exit(400, resp_body)
      end

      local pids = ngx_worker_pids()
      if pid == ngx_worker_pid() and #pids > 1 then
        local current_pid = ngx_worker_pid()
        local idx = 1

        for i = 1, #pids do
          if pids[i] == current_pid then
            idx = i
            break
          end
        end

        --[[
          Removing the current pid from the list of pids to avoid
          dumping the snapshot of the current worker beacause it
          will be blocked until the snapshot is done.
        --]]
        table_remove(pids, idx)

        pid = pids[math_random(#pids)]
      end

      local path = string_format("%s/profiling/gc-snapshot-%d-%d.bin",
                                 kong.configuration.prefix, pid, ngx_time())

      local ok, err = kong.worker_events.post("profiling", "gc-snapshot", {
        pid = pid,
        timeout = timeout,
        path = path,
      })

      if not ok then
        local resp_body = {
          status = "error",
          message = "failed to post worker event: " .. err,
        }
        return kong.response.exit(500, resp_body)
      end

      local resp_body = {
        status = "started",
        message = "Dumping snapshot in progress on pid: " .. pid,
      }
      return kong.response.exit(201, resp_body)
    end,
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
