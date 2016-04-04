local nginx_conf_compiler = require "kong.cmd.utils.nginx_conf_compiler"
local nginx_signals = require "kong.cmd.utils.nginx_signals"
local serf_signals = require "kong.cmd.utils.serf_signals"
local conf_loader = require "kong.conf_loader"
local DAOFactory = require "kong.dao.factory"
local log = require "kong.cmd.utils.log"

local function execute(args)
  local conf = assert(conf_loader(args.conf, {
    prefix = args.prefix
  }))

  assert(nginx_conf_compiler.prepare_prefix(conf, conf.prefix))
  assert(serf_signals.start(conf, conf.prefix, DAOFactory(conf)))
  assert(nginx_signals.reload(conf.prefix))
  log("Reloaded")
end

local lapp = [[
Usage: kong reload [OPTIONS]

Options:
 -c,--conf (optional string) configuration file
 --prefix  (optional string) Nginx prefix path
]]

return {
  lapp = lapp,
  execute = execute
}
