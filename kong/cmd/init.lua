require("kong.globalpatches")({cli = true})

math.randomseed() -- Generate PRNG seed

local pl_app = require "pl.lapp"
local log = require "kong.cmd.utils.log"

local options = [[
 --v              verbose
 --vv             debug
]]

local cmds_arr = {}
local cmds = {
  start = true,
  stop = true,
  quit = true,
  restart = true,
  reload = true,
  health = true,
  check = true,
  prepare = true,
  migrations = true,
  version = true,
  config = true,
  roar = true,
  hybrid = true,
}

for k in pairs(cmds) do
  cmds_arr[#cmds_arr+1] = k
end

table.sort(cmds_arr)

local help = string.format([[
Usage: kong COMMAND [OPTIONS]

The available commands are:
 %s

Options:
%s]], table.concat(cmds_arr, "\n "), options)

return function(args)
  local cmd_name = table.remove(args, 1)
  if not cmd_name then
    pl_app(help)
    pl_app.quit()
  elseif not cmds[cmd_name] then
    pl_app(help)
    pl_app.quit("No such command: " .. cmd_name)
  end

  local cmd = require("kong.cmd." .. cmd_name)
  local cmd_lapp = cmd.lapp
  local cmd_exec = cmd.execute

  if cmd_lapp then
    cmd_lapp = cmd_lapp .. options -- append universal options
    args = pl_app(cmd_lapp)
  end

  -- check sub-commands
  if cmd.sub_commands then
    local sub_cmd = table.remove(args, 1)
    if not sub_cmd then
      pl_app.quit()
    elseif not cmd.sub_commands[sub_cmd] then
      pl_app.quit("No such command for " .. cmd_name .. ": " .. sub_cmd)
    else
      args.command = sub_cmd
    end
  end

  -- verbose mode
  if args.v then
    log.set_lvl(log.levels.verbose)
  elseif args.vv then
    log.set_lvl(log.levels.debug)
  end

  log.verbose("Kong: %s", _KONG._VERSION)
  log.debug("ngx_lua: %s", ngx.config.ngx_lua_version)
  log.debug("nginx: %s", ngx.config.nginx_version)
  log.debug("Lua: %s", jit and jit.version or _VERSION)

  xpcall(function() cmd_exec(args) end, function(err)
    if not (args.v or args.vv) then
      err = err:match "^.-:.-:.(.*)$"
      io.stderr:write("Error: " .. err .. "\n")
      io.stderr:write("\n  Run with --v (verbose) or --vv (debug) for more details\n")
    else
      local trace = debug.traceback(err, 2)
      io.stderr:write("Error: \n")
      io.stderr:write(trace .. "\n")
    end

    pl_app.quit(nil, true)
  end)
end
