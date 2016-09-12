local dnsmasq_signals = require "kong.cmd.utils.dnsmasq_signals"
local prefix_handler = require "kong.cmd.utils.prefix_handler"
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
  assert(dao:run_migrations())
  assert(prefix_handler.prepare_prefix(conf, args.nginx_conf))
  if conf.dnsmasq then
    assert(dnsmasq_signals.start(conf))
  end
  assert(serf_signals.start(conf, dao))
  assert(nginx_signals.start(conf))
  log("Kong started")
end

local lapp = [[
Usage: kong start [OPTIONS]

Start Kong (Nginx and other configured services) in the configured
prefix directory.

Options:
 -c,--conf    (optional string) configuration file
 -p,--prefix  (optional string) override prefix directory
 --nginx-conf (optional string) custom Nginx configuration template
]]

return {
  lapp = lapp,
  execute = execute
}
