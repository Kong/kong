local pl_app = require "pl.lapp"
local log = require "kong.cmd.utils.log"

local options = [[
 --trace (optional boolean) with traceback
 --v     (optional boolean) verbose
 --vv    (optional boolean) debug
]]

local help = [[
Usage: kong COMMAND [OPTIONS]

The available commands are:
 start
 stop
 migrations

Options:
]]..options

local cmds = {
  start = "start",
  stop = "stop",
  --reload = "reload",
  migrations = "migrations"
}

return function(args)
  local cmd_name = args[1]
  if not cmd_name then
    pl_app(help)
    pl_app.quit()
  elseif not cmds[cmd_name] then
    pl_app(help)
    pl_app.quit("No such command: "..cmd_name)
  end

  local cmd = require("kong.cmd."..cmd_name)
  local cmd_lapp = cmd.lapp
  local cmd_exec = cmd.execute

  cmd_lapp = cmd_lapp..options -- append universal options
  args = pl_app(cmd_lapp)

  -- check sub-commands
  if cmd.sub_commands then
    local sub_cmd = table.remove(args, 2)
    if not sub_cmd then
      pl_app.quit()
    elseif not cmd.sub_commands[sub_cmd] then
      pl_app.quit("No such command for "..cmd_name..": "..sub_cmd)
    else
      args.command = sub_cmd
    end
  end

  -- verbose mode
  if args.verbose then
    log.set_lvl(log.levels.verbose)
  elseif args.vv then
    log.set_lvl(log.levels.debug)
  end

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
