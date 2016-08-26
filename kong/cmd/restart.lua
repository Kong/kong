local stop = require "kong.cmd.stop"
local start = require "kong.cmd.start"
local conf_loader = require "kong.conf_loader"

local function execute(args)
  if args.conf then
    -- retrieve the prefix for stop
    local conf = assert(conf_loader(args.conf))
    args.prefix = conf.prefix
  end

  pcall(stop.execute, args)
  start.execute(args)
end

local lapp = [[
Usage: kong restart [OPTIONS]

Restart a Kong node (and other configured services like Serf)
in the given prefix directory.

This command is equivalent to doing both 'kong stop' and
'kong start'.

Options:
 -c,--conf    (optional string) configuration file
 -p,--prefix  (optional string) prefix at which Kong should be running
 --nginx-conf (optional string) custom Nginx configuration template
]]

return {
  lapp = lapp,
  execute = execute
}
