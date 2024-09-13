------------------------------------------------------------------
-- Collection of utilities to help testing Kong features and plugins.
--
-- @copyright Copyright 2016-2022 Kong Inc. All rights reserved.
-- @license [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
-- @module spec.helpers


local shell = require("resty.shell")


local CONSTANTS = require("spec.internal.constants")


-- Reads the pid from a pid file and returns it, or nil + err
local function get_pid_from_file(pid_path)
  local pid
  local fd, err = io.open(pid_path)
  if not fd then
    return nil, err
  end

  pid = fd:read("*l")
  fd:close()

  return pid
end


local function pid_dead(pid, timeout)
  local max_time = ngx.now() + (timeout or 10)

  repeat
    if not shell.run("ps -p " .. pid .. " >/dev/null 2>&1", nil, 0) then
      return true
    end
    -- still running, wait some more
    ngx.sleep(0.05)
  until ngx.now() >= max_time

  return false
end


-- Waits for the termination of a pid.
-- @param pid_path Filename of the pid file.
-- @param timeout (optional) in seconds, defaults to 10.
local function wait_pid(pid_path, timeout, is_retry)
  local pid = get_pid_from_file(pid_path)

  if CONSTANTS.TEST_COVERAGE_MODE == "true" then
    timeout = CONSTANTS.TEST_COVERAGE_TIMEOUT
  end

  if pid then
    if pid_dead(pid, timeout) then
      return
    end

    if is_retry then
      return
    end

    -- Timeout reached: kill with SIGKILL
    shell.run("kill -9 " .. pid .. " >/dev/null 2>&1", nil, 0)

    -- Sanity check: check pid again, but don't loop.
    wait_pid(pid_path, timeout, true)
  end
end


return {
  get_pid_from_file = get_pid_from_file,
  pid_dead = pid_dead,
  wait_pid = wait_pid,
}

