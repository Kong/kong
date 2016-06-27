local dnsmasq_signals = require "kong.cmd.utils.dnsmasq_signals"
local prefix_handler = require "kong.cmd.utils.prefix_handler"
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

  assert(prefix_handler.prepare_prefix(conf, conf.prefix))
  assert(dnsmasq_signals.start(conf, conf.prefix))
  assert(serf_signals.start(conf, conf.prefix, DAOFactory(conf)))
  assert(nginx_signals.reload(conf.prefix))
  log("Reloaded")
end

local lapp = [[
Usage: kong reload [OPTIONS]

Options:
 --prefix (optional string) prefix Kong is running at
]]

return {
  lapp = lapp,
  execute = execute
}
