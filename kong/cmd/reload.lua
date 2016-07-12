local dnsmasq_signals = require "kong.cmd.utils.dnsmasq_signals"
local prefix_handler = require "kong.cmd.utils.prefix_handler"
local nginx_signals = require "kong.cmd.utils.nginx_signals"
local serf_signals = require "kong.cmd.utils.serf_signals"
local conf_loader = require "kong.conf_loader"
local DAOFactory = require "kong.dao.factory"
local pl_path = require "pl.path"
local log = require "kong.cmd.utils.log"

local function execute(args)
  -- retrieve prefix or use given one
  local default_conf = assert(conf_loader(nil, {
    prefix = args.prefix
  }))
  assert(pl_path.exists(default_conf.prefix),
    "no such prefix: "..default_conf.prefix)

  -- load <PREFIX>/kong.conf containing running node's config
  local conf = assert(conf_loader(default_conf.kong_conf))
  assert(prefix_handler.prepare_prefix(conf))
  assert(dnsmasq_signals.start(conf))
  assert(serf_signals.start(conf, DAOFactory(conf)))
  assert(nginx_signals.reload(conf))
  log("Reloaded")
end

local lapp = [[
Usage: kong reload [OPTIONS]

Options:
 -p,--prefix (optional string) prefix Kong is running at
]]

return {
  lapp = lapp,
  execute = execute
}
