local dnsmasq_signals = require "kong.cmd.utils.dnsmasq_signals"
local nginx_signals = require "kong.cmd.utils.nginx_signals"
local serf_signals = require "kong.cmd.utils.serf_signals"
local conf_loader = require "kong.conf_loader"
local DAOFactory = require "kong.dao.factory"
local log = require "kong.cmd.utils.log"

local function execute(args)
  local conf = assert(conf_loader(args.conf, {
    prefix = args.prefix
  }))

  local dao = DAOFactory(conf)
  assert(nginx_signals.stop(conf.prefix))
  assert(serf_signals.stop(conf, conf.prefix, dao))
  if conf.dnsmasq then
    assert(dnsmasq_signals.stop(conf.prefix))
  end
  log("Stopped")
end

local lapp = [[
Usage: kong stop [OPTIONS]

Options:
 -c,--conf (optional string) configuration file
 --prefix (optional string) Nginx prefix path
]]

return {
  lapp = lapp,
  execute = execute
}
