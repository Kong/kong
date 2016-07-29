local pl_path = require "pl.path"

local cmd_tmpl = [[
kill %s `cat %s` >/dev/null 2>&1
]]

local function kill(pid_file, args)
  local cmd = string.format(cmd_tmpl, args or "-0", pid_file)
  return os.execute(cmd)
end

local function is_running(pid_file)
  if pl_path.exists(pid_file) then
    return kill(pid_file) == 0
  end
end

return {
  kill = kill,
  is_running = is_running
}
