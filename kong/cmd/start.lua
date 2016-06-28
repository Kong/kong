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
  assert(prefix_handler.prepare_prefix(conf))
  if conf.dnsmasq then
    assert(dnsmasq_signals.start(conf))
  end
  assert(serf_signals.start(conf, dao))
  assert(nginx_signals.start(conf))
  log("Started")
end

local lapp = [[
Usage: kong start [OPTIONS]

Options:
 -c,--conf (optional string) configuration file
 --prefix  (optional string) override prefix directory
]]

return {
  lapp = lapp,
  execute = execute
}
