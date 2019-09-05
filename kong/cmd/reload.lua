local prefix_handler = require "kong.cmd.utils.prefix_handler"
local nginx_signals = require "kong.cmd.utils.nginx_signals"
local conf_loader = require "kong.conf_loader"
local pl_path = require "pl.path"
local log = require "kong.cmd.utils.log"

local function execute(args)
  log.disable()
  -- retrieve prefix or use given one
  local default_conf = assert(conf_loader(args.conf, {
    prefix = args.prefix
  }))
  log.enable()
  assert(pl_path.exists(default_conf.prefix),
         "no such prefix: " .. default_conf.prefix)

  -- load <PREFIX>/kong.conf containing running node's config
  local conf = assert(conf_loader(args.conf, {
    prefix = args.prefix
  }))
  assert(prefix_handler.prepare_prefix(conf, args.nginx_conf))

  assert(nginx_signals.reload(conf))
  log("Kong reloaded")
end

local lapp = [[
Usage: kong reload [OPTIONS]

Reload a Kong node (and start other configured services
if necessary) in given prefix directory.

This command sends a HUP signal to Nginx, which will spawn
new workers (taking configuration changes into account),
and stop the old ones when they have finished processing
current requests.

Options:
 -c,--conf        (optional string) configuration file
 -p,--prefix      (optional string) prefix Kong is running at
 --nginx-conf     (optional string) custom Nginx configuration template
]]

return {
  lapp = lapp,
  execute = execute
}
