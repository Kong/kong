local dnsmasq_signals = require "kong.cmd.utils.dnsmasq_signals"
local nginx_signals = require "kong.cmd.utils.nginx_signals"
local serf_signals = require "kong.cmd.utils.serf_signals"
local conf_loader = require "kong.conf_loader"
local DAOFactory = require "kong.dao.factory"
local pl_path = require "pl.path"
local log = require "kong.cmd.utils.log"

local function execute(args)
  local default_conf = assert(conf_loader()) -- just retrieve default prefix
  local prefix = args.prefix or default_conf.prefix
  assert(pl_path.exists(prefix), "no such prefix: "..prefix)

  local conf_path = pl_path.join(prefix, "kong.conf")
  local conf = assert(conf_loader(conf_path, {
    prefix = prefix
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
 --prefix (optional string) prefix Kong is running at
]]

return {
  lapp = lapp,
  execute = execute
}
