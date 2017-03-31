local pl_path = require "pl.path"
local pl_utils = require "pl.utils"
local log = require "kong.cmd.utils.log"

local cmd_tmpl = [[kill %s `cat %s` >/dev/null 2>&1]]

local function kill(pid_file, args)
  log.debug("sending signal to pid at: %s", pid_file)
  local cmd = string.format(cmd_tmpl, args or "-0", pid_file)
  if pl_path.exists(pid_file) then
    log.debug(cmd)
    local _, code = pl_utils.execute(cmd)
    return code
  else
    log.debug("no pid file at: %s", pid_file)
    return 0
  end
end

local function is_running(pid_file)
  -- we do our own pid_file exists check here because
  -- we want to return `nil` in case of NOT running,
  -- and not `0` like `kill` would return.
  if pl_path.exists(pid_file) then
    return kill(pid_file) == 0
  end
end

return {
  kill = kill,
  is_running = is_running
}
