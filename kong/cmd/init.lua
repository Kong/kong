local pl_app = require "pl.lapp"
local help = [[
Kong, open-source API gateway.

Usage: kong COMMAND [OPTIONS]

The available commands are:
 start
 stop

Options:
 --trace (optional boolean) with traceback
]]

local DEFAULT_NGINX_PREFIX = "servroot"

local cmds = {
  start = "start",
  stop = "stop",
  --reload = "reload",
  --migrate = "migrate",
  --reset = "reset"
}

return function(args)
  local cmd_name = args[1]
  if cmd_name == nil then
    pl_app(help)
    pl_app.quit()
  elseif not cmds[cmd_name] then
    pl_app(help)
    pl_app.quit("No such command: "..cmd_name)
  end

  local cmd = require("kong.cmd."..cmd_name)
  local cmd_lapp = cmd.lapp
  local cmd_exec = cmd.execute

  cmd_lapp = cmd_lapp.."\n  --trace (optional boolean) with traceback\n"
  args = pl_app(cmd_lapp)
  args.prefix = args.prefix or DEFAULT_NGINX_PREFIX

  xpcall(function() cmd_exec(args) end, function(err)
    if not args.trace then
      err = err:match "^.-:.-:.(.*)$"
      io.stderr:write("Error: "..err.."\n")
      io.stderr:write("\n  Run with --trace to see traceback\n")
    else
      local trace = debug.traceback(err, 2)
      io.stderr:write("Error: \n")
      io.stderr:write(trace.."\n")
    end

    pl_app.quit(nil, true)
  end)
end
