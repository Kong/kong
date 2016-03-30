local nginx_conf_compiler = require "kong.cmd.utils.nginx_conf_compiler"
local nginx_signals = require "kong.cmd.utils.nginx_signals"
local serf_signals = require "kong.cmd.utils.serf_signals"
local conf_loader = require "kong.conf_loader"
local DAOFactory = require "kong.dao.factory"

local function execute(args)
  local conf = assert(conf_loader(args.conf))
  assert(nginx_conf_compiler.prepare_prefix(conf, args.prefix))
  assert(serf_signals.start(conf, args.prefix, DAOFactory(conf)))
  assert(nginx_signals.start(args.prefix))
  print("Started")
end

local lapp = [[
Usage: kong start [OPTIONS]

Options:
 -c,--conf (optional string) configuration file
 --prefix  (optional string) Nginx prefix path
]]

return {
  lapp = lapp,
  execute = execute
}
