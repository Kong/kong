local nginx_conf_compiler = require "kong.cmd.utils.nginx_conf_compiler"
local nginx_signals = require "kong.cmd.utils.nginx_signals"
local serf_signals = require "kong.cmd.utils.serf_signals"
local conf_loader = require "kong.conf_loader"
local DAOFactory = require "kong.dao.factory"
local log = require "kong.cmd.utils.log"

--[[
Start Kong.

Kong being a bundle of several applications and services, start acts
as follows:
--]]

local function execute(args)
  local conf = assert(conf_loader(args.conf, {
    prefix = args.prefix
  }))

  local dao = DAOFactory(conf)
  assert(dao:run_migrations())
  assert(nginx_conf_compiler.prepare_prefix(conf, conf.prefix))
  assert(serf_signals.start(conf, conf.prefix, dao))
  assert(nginx_signals.start(conf.prefix))
  log("Started")
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
