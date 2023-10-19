-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson                              = require("cjson.safe")
local set_log_level                      = require("resty.kong.log").set_log_level
local get_log_level                      = require("resty.kong.log").get_log_level
local constants                          = require("kong.constants")

-- XXX EE [[
local profiling                          = require("kong.enterprise_edition.profiling")
-- ]]

local LOG_LEVELS                         = constants.LOG_LEVELS
local DYN_LOG_LEVEL_KEY                  = constants.DYN_LOG_LEVEL_KEY
local DYN_LOG_LEVEL_TIMEOUT_AT_KEY       = constants.DYN_LOG_LEVEL_TIMEOUT_AT_KEY

local ngx                                = ngx
local kong                               = kong
local pcall                              = pcall
local type                               = type
local tostring                           = tostring
local string_format                      = string.format
local math_max                           = math.max
local math_random                        = math.random
local table_remove                       = table.remove

local ngx_time                           = ngx.time
local ngx_worker_pids                    = ngx.worker.pids -- luacheck: ignore
local ngx_worker_pid                     = ngx.worker.pid

local NODE_LEVEL_BROADCAST               = false
local CLUSTER_LEVEL_BROADCAST            = true
local DEFAULT_LOG_LEVEL_TIMEOUT          = 60          -- 60s

local MIN_PROFILING_TIMEOUT              = 1           -- seconds
local MAX_PROFILING_TIMEOUT              = 600         -- seconds
local MIN_TRACING_TIMEOUT                = 1           -- seconds

local DEFAULT_CPU_PROFILING_MODE         = "time"
local DEFAULT_CPU_PROFILING_STEP         = 500
local DEFAULT_CPU_PROFILING_INTERVAL     = 10000       -- microseconds
local DEFAULT_CPU_PROFILING_TIMEOUT      = 10          -- seconds
local MIN_CPU_PROFILING_STEP             = 50
local MAX_CPU_PROFILING_STEP             = 1000
local MIN_CPU_PROFILING_INTERVAL         = 1           -- microseconds
local MAX_CPU_PROFILING_INTERVAL         = 1000000     -- microseconds

local DEFAULT_GC_SNAPSHOT_TIMEOUT        = 120         -- seconds

local DEFAULT_MEMORY_TRACING_TIMEOUT     = 10          -- seconds
local DEFAULT_MEMORY_TRACING_STACK_DEPTH = 8
local DEFAULT_MEMORY_TRACING_BLOCK_SIZE  = 2^20 * 512  -- 512 MiB
local MIN_MEMORY_TRACING_BLOCK_SIZE      = 2^20 * 512  -- 512 MiB
local MAX_MEMORY_TRACING_BLOCK_SIZE      = 2^30 * 5    -- 5 GiB
local MIN_MEMORY_TRACING_STACK_DEPTH     = 1
local MAX_MEMORY_TRACING_STACK_DEPTH     = 64          -- 64 frames
                                                       -- this number was hard coded
                                                       -- in our implementation

local ERR_MSG_INVALID_PROFILING_TIMEOUT  = string.format(
                                           "Invalid timeout (must be between %d and %d): ",
                                           MIN_PROFILING_TIMEOUT, MAX_PROFILING_TIMEOUT
                                         )

local ERR_MSG_INVALID_TRACING_TIMEOUT    = string.format(
                                           "Invalid timeout (must be greater than %d): ",
                                           MIN_TRACING_TIMEOUT
                                         )

local ERR_MSG_INVALID_STEP               = string.format(
                                           "Invalid step (must be between %d and %d): ",
                                           MIN_CPU_PROFILING_STEP, MAX_CPU_PROFILING_STEP
                                         )

local ERR_MSG_INVALID_INTERVAL           = string.format(
                                           "Invalid interval (must be between %d and %d): ",
                                           MIN_CPU_PROFILING_INTERVAL, MAX_CPU_PROFILING_INTERVAL
                                         )

local ERR_MSG_INVALID_MODE               = "Invalid mode (must be 'time' or 'instruction'): "

local ERR_MSG_INVALID_BLOCK_SIZE         = string.format(
                                           "Invalid block size (must be between %d and %d): ",
                                           MIN_MEMORY_TRACING_BLOCK_SIZE, MAX_MEMORY_TRACING_BLOCK_SIZE
                                         )

local ERR_MSG_INVALID_STACK_DEPTH        = string.format(
                                           "Invalid stack depth (must be between %d and %d): ",
                                           MIN_MEMORY_TRACING_STACK_DEPTH,
                                           MAX_MEMORY_TRACING_STACK_DEPTH
                                         )


local function handle_put_log_level(self, broadcast)
  if kong.configuration.database == "off" then
    local message = "Cannot change log level when not using a database"
    return kong.response.exit(405, { message = message })
  end

  local log_level = LOG_LEVELS[self.params.log_level]
  local timeout = math.ceil(tonumber(self.params.timeout) or DEFAULT_LOG_LEVEL_TIMEOUT)

  if type(log_level) ~= "number" then
    return kong.response.exit(400, { message = "Unknown log level: " .. self.params.log_level })
  end

  if timeout < 0 then
    return kong.response.exit(400, { message = "Timeout must be greater than or equal to 0" })
  end

  local cur_log_level = get_log_level(LOG_LEVELS[kong.configuration.log_level])

  if cur_log_level == log_level then
    local message = "Log level is already " .. self.params.log_level
    return kong.response.exit(200, { message = message })
  end

  local ok, err = pcall(set_log_level, log_level, timeout)

  if not ok then
    local message = "Failed setting log level: " .. err
    return kong.response.exit(500, { message = message })
  end

  local data = {
    log_level = log_level,
    timeout = timeout,
  }

  -- broadcast to all workers in a node
  ok, err = kong.worker_events.post("debug", "log_level", data)

  if not ok then
    local message = "Failed broadcasting to workers: " .. err
    return kong.response.exit(500, { message = message })
  end

  if broadcast then
    -- broadcast to all nodes in a cluster
    ok, err = kong.cluster_events:broadcast("log_level", cjson.encode(data))

    if not ok then
      local message = "Failed broadcasting to cluster: " .. err
      return kong.response.exit(500, { message = message })
    end
  end

  -- store in shm so that newly spawned workers can update their log levels
  ok, err = ngx.shared.kong:set(DYN_LOG_LEVEL_KEY, log_level, timeout)

  if not ok then
    local message = "Failed storing log level in shm: " .. err
    return kong.response.exit(500, { message = message })
  end

  ok, err = ngx.shared.kong:set(DYN_LOG_LEVEL_TIMEOUT_AT_KEY, ngx.time() + timeout, timeout)

  if not ok then
    local message = "Failed storing the timeout of log level in shm: " .. err
    return kong.response.exit(500, { message = message })
  end

  return kong.response.exit(200, { message = "Log level changed to " .. LOG_LEVELS[log_level]})
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


local function make_profiling_data_path(name, pid, has_suffix)
  local fmt = "%s/profiling/%s-%d-%d"
  if has_suffix then
    fmt = fmt .. ".bin"
  end


  return string_format(fmt,
                       kong.configuration.prefix,
                       name,
                       pid,
                       ngx_time())
end


local function response_body(status, message)
  return {
    status  = status,
    message = message,
  }
end


local routes = {
  ["/debug/node/log-level"] = {
    GET = function(self)
      local cur_level = get_log_level(LOG_LEVELS[kong.configuration.log_level])

      if type(LOG_LEVELS[cur_level]) ~= "string" then
        local message = "Unknown log level: " .. tostring(cur_level)
        return kong.response.exit(500, { message = message })
      end

      return kong.response.exit(200, { message = "Current log level: " .. LOG_LEVELS[cur_level] })
    end,
  },
  ["/debug/node/log-level/:log_level"] = {
    PUT = function(self)
      return handle_put_log_level(self, NODE_LEVEL_BROADCAST)
    end
  },
  ["/debug/profiling/cpu"] = {
    GET = function(self)
      local state = profiling.cpu.state()

      if state.status == "started" then
        state.remain = math_max(state.timeout_at - ngx_time(), 0)
        state.timeout_at = nil
      end

      return kong.response.exit(200, state)
    end,

    POST = function(self)
      local state = profiling.cpu.state()

      if state.status == "started" then
        return kong.response.exit(409, response_body("error", "Profiling is already active on pid: " .. state.pid))
      end

      local pid       = tonumber(self.params.pid)       or ngx_worker_pid()
      local mode      = self.params.mode                or DEFAULT_CPU_PROFILING_MODE
      local step      = tonumber(self.params.step)      or DEFAULT_CPU_PROFILING_STEP
      local interval  = tonumber(self.params.interval)  or DEFAULT_CPU_PROFILING_INTERVAL
      local timeout   = tonumber(self.params.timeout)   or DEFAULT_CPU_PROFILING_TIMEOUT

      if not is_valid_worker_pid(pid) then
        return kong.response.exit(400, response_body("error", "Invalid pid: " .. pid))
      end

      if mode ~= "time" and mode ~= "instruction" then
        return kong.response.exit(400, response_body("error", ERR_MSG_INVALID_MODE .. mode))
      end

      if step < MIN_CPU_PROFILING_STEP or step > MAX_CPU_PROFILING_STEP then
        return kong.response.exit(400, response_body("error", ERR_MSG_INVALID_STEP .. step))
      end

      if interval < MIN_CPU_PROFILING_INTERVAL or interval > MAX_CPU_PROFILING_INTERVAL then
        return kong.response.exit(400, response_body("error", ERR_MSG_INVALID_INTERVAL .. interval))
      end

      if timeout < MIN_PROFILING_TIMEOUT or timeout > MAX_PROFILING_TIMEOUT then
        return kong.response.exit(400, response_body("error", ERR_MSG_INVALID_PROFILING_TIMEOUT .. timeout))
      end

      local ok, err = profiling.cpu.start(mode, step, interval, timeout,
                                          make_profiling_data_path("prof", pid, true),
                                          pid)

      if not ok then
        return kong.response.exit(500, response_body("error", "Failed to start: " .. err))
      end

      return kong.response.exit(201, response_body("started", "Profiling is activated on pid: " .. pid))
    end,

    DELETE = function(self)
      local state = profiling.cpu.state()

      if state.status ~= "started" then
        return kong.response.exit(400, response_body("error", "Profiling is not active"))
      end

      local ok, err = profiling.cpu.stop()

      if not ok then
        return kong.response.exit(500, response_body("error", "Failed to stop: " .. err))
      end

      ngx.header["X-Kong-Profiling-State"] = cjson.encode(state)

      return kong.response.exit(204)
    end,
  },
  ["/debug/profiling/gc-snapshot"] = {
    GET = function(self)
      local state = profiling.gc_snapshot.state()

      if state.status == "started" then
        state.remain = math_max(state.timeout_at - ngx_time(), 0)
        state.timeout_at = nil
      end

      return kong.response.exit(200, state)
    end,
    POST = function(self)
      local state = profiling.gc_snapshot.state()

      if state.status == "started" then
        return kong.response.exit(409, response_body("error", "Profiling is already active on pid: " .. state.pid))
      end

      local pid     = tonumber(self.params.pid)     or ngx_worker_pid()
      local timeout = tonumber(self.params.timeout) or DEFAULT_GC_SNAPSHOT_TIMEOUT

      if timeout < MIN_PROFILING_TIMEOUT or timeout > MAX_PROFILING_TIMEOUT then
        return kong.response.exit(400, response_body("error", ERR_MSG_INVALID_PROFILING_TIMEOUT .. timeout))
      end

      if not is_valid_worker_pid(pid) then
        return kong.response.exit(400, response_body("error", "Invalid pid: " .. pid))
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

      local ok, err = profiling.gc_snapshot.dump(make_profiling_data_path("gc-snapshot", pid, true),
                                                 timeout, pid)

      if not ok then
        return kong.response.exit(500, response_body("error", "Failed to start: " .. err))
      end

      return kong.response.exit(201, response_body("started", "Dumping snapshot in progress on pid: " .. pid))
    end,
  },
  ["/debug/profiling/memory"] = {
    GET = function(self)
      local state = profiling.memory.state()

      if state.status == "started" then
        state.remain = math_max(state.timeout_at - ngx_time(), 0)
        state.timeout_at = nil
      end

      return kong.response.exit(200, state)
    end,

    POST = function(self)
      local state = profiling.memory.state()

      if state.status == "started" then
        return kong.response.exit(409, response_body("error", "Profiling is already active on pid: " .. state.pid))
      end

      local pid         = tonumber(self.params.pid)         or ngx_worker_pid()
      local timeout     = tonumber(self.params.timeout)     or DEFAULT_MEMORY_TRACING_TIMEOUT
      local block_size  = tonumber(self.params.block_size)  or DEFAULT_MEMORY_TRACING_BLOCK_SIZE
      local stack_depth = tonumber(self.params.stack_depth) or DEFAULT_MEMORY_TRACING_STACK_DEPTH

      if not is_valid_worker_pid(pid) then
        return kong.response.exit(400, response_body("error", "Invalid pid: " .. pid))
      end

      if timeout < MIN_TRACING_TIMEOUT then
        return kong.response.exit(400, response_body("error", ERR_MSG_INVALID_TRACING_TIMEOUT .. timeout))
      end

      if block_size < MIN_MEMORY_TRACING_BLOCK_SIZE or block_size > MAX_MEMORY_TRACING_BLOCK_SIZE then
        return kong.response.exit(400, response_body("error", ERR_MSG_INVALID_BLOCK_SIZE .. block_size))
      end

      if stack_depth < MIN_MEMORY_TRACING_STACK_DEPTH or stack_depth > MAX_MEMORY_TRACING_STACK_DEPTH then
        return kong.response.exit(400, response_body("error", ERR_MSG_INVALID_STACK_DEPTH .. stack_depth))
      end

      local ok, err = profiling.memory.start(make_profiling_data_path("trace", pid, false),
                                             timeout, block_size, stack_depth, pid)

      if not ok then
        return kong.response.exit(500, response_body("error", "Failed to start: " .. err))
      end

      return kong.response.exit(201, response_body("started", "Profiling is activated on pid: " .. pid))
    end,

    DELETE = function(self)
      local state = profiling.memory.state()

      if state.status ~= "started" then
        return kong.response.exit(400, response_body("error", "Profiling is not active"))
      end

      local ok, err = profiling.memory.stop()

      if not ok then
        return kong.response.exit(500, response_body("error", "Failed to stop: " .. err))
      end

      ngx.header["X-Kong-Profiling-State"] = cjson.encode(state)

      return kong.response.exit(204)
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
