local dnsmasq_signals = require "kong.cmd.utils.dnsmasq_signals"
local nginx_signals = require "kong.cmd.utils.nginx_signals"
local serf_signals = require "kong.cmd.utils.serf_signals"
local conf_loader = require "kong.conf_loader"
local DAOFactory = require "kong.dao.factory"
local pl_path = require "pl.path"
local log = require "kong.cmd.utils.log"

local function execute(args)
  log.disable()
  -- only to retrieve the default prefix or use given one
  local default_conf = assert(conf_loader(nil, {
    prefix = args.prefix
  }))
  log.enable()
  assert(pl_path.exists(default_conf.prefix),
         "no such prefix: "..default_conf.prefix)

  -- load <PREFIX>/kong.conf containing running node's config
  local conf = assert(conf_loader(default_conf.kong_conf))
  assert(nginx_signals.stop(conf))
  assert(serf_signals.stop(conf, DAOFactory(conf)))
  if conf.dnsmasq then
    assert(dnsmasq_signals.stop(conf))
  end
  log("Kong stopped")
end

local lapp = [[
Usage: kong stop [OPTIONS]

Stop a running Kong node (Nginx and other configured services) in given
prefix directory.

This command sends a SIGTERM signal to Nginx.

Options:
 -p,--prefix (optional string) prefix Kong is running at
]]

return {
  lapp = lapp,
  execute = execute
}
