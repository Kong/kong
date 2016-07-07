local conf_loader = require "kong.conf_loader"
local stop = require "kong.cmd.stop"
local start = require "kong.cmd.start"

local function execute(args)
  local conf = assert(conf_loader(args.conf))
  args.prefix = conf.prefix -- Required for stop

  pcall(stop.execute, args)
  start.execute(args)
end

local lapp = [[
Usage: kong restart [OPTIONS]

Options:
 -c,--conf (optional string) configuration file
 --prefix  (optional string) override prefix directory
]]

return {
  lapp = lapp,
  execute = execute
}