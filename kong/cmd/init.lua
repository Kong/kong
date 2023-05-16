require("kong.globalpatches")({cli = true})

math.randomseed() -- Generate PRNG seed

local pl_app = require "pl.lapp"
local log = require "kong.cmd.utils.log"
local inject_directives = require "kong.cmd.utils.inject_directives"

local function stop_timers()
  -- shutdown lua-resty-timer-ng to allow the nginx worker to stop quickly
  if _G.timerng then
    _G.timerng:destroy()
  end
end

local options = [[
 --v              verbose
 --vv             debug
]]

local internal_options = [[
 --no-resty-cli-injection             not inject nginx directives to resty cli
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
  vault = true,
}

local inject_cmds = {
  vault = true,
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

options = options .. internal_options

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

  -- inject necessary nginx directives (e.g. lmdb_*, lua_ssl_*)
  -- into the temporary nginx.conf that `resty` will create
  if inject_cmds[cmd_name] and not args.no_resty_cli_injection then
    log.verbose("start to inject nginx directives and respawn")
    inject_directives.run_command_with_injection(cmd_name, args)
    return
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

  stop_timers()
end
