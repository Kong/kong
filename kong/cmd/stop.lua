local nginx_signals = require "kong.cmd.utils.nginx_signals"
local serf_signals = require "kong.cmd.utils.serf_signals"

local function execute(args)
  assert(nginx_signals.stop(args.prefix))
  assert(serf_signals.stop(args.prefix))
  print("Stopped")
end

local lapp = [[
Usage: kong stop [OPTIONS]

Options:
 --prefix (optional string) Nginx prefix path
]]

return {
  lapp = lapp,
  execute = execute
}
