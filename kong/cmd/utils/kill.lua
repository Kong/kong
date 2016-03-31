local cmd_tmpl = [[
kill %s `cat %s` >/dev/null 2>&1
]]

local function kill(pid_file, args)
  local cmd = string.format(cmd_tmpl, args or "-0", pid_file)
  return os.execute(cmd)
end

return kill
