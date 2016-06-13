local nginx_signals = require "kong.cmd.utils.nginx_signals"
local serf_signals = require "kong.cmd.utils.serf_signals"
local dnsmasq_signals = require "kong.cmd.utils.dnsmasq_signals"
local conf_loader = require "kong.conf_loader"
local DAOFactory = require "kong.dao.factory"
local log = require "kong.cmd.utils.log"

local function execute(args)
  -- no conf file loaded, we just want the prefix,
  -- potentially overriden by the argument
  local conf = assert(conf_loader(nil, {
    prefix = args.prefix
  }))

  local dao = DAOFactory(conf)

  assert(nginx_signals.stop(conf.prefix))
  assert(serf_signals.stop(conf, conf.prefix, dao))
  assert(dnsmasq_signals.stop(conf.prefix))
  log("Stopped")
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
