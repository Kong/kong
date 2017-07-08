local prefix_handler = require "kong.cmd.utils.prefix_handler"
local nginx_signals = require "kong.cmd.utils.nginx_signals"
local conf_loader = require "kong.conf_loader"
local DAOFactory = require "kong.dao.factory"
local kill = require "kong.cmd.utils.kill"
local log = require "kong.cmd.utils.log"

local function execute(args)
  local conf = assert(conf_loader(args.conf, {
    prefix = args.prefix
  }))

  assert(not kill.is_running(conf.nginx_pid),
         "Kong is already running in " .. conf.prefix)

  local err
  local dao = assert(DAOFactory.new(conf))
  xpcall(function()
    assert(prefix_handler.prepare_prefix(conf, args.nginx_conf))
    if not dao.db:migrations_initialized() or not args.no_migrations then
      assert(dao:run_migrations())
    end
    assert(dao:are_migrations_uptodate())
    assert(nginx_signals.start(conf))
    log("Kong started")
  end, function(e)
    err = e -- cannot throw from this function
  end)

  if err then
    log.verbose("could not start Kong, stopping services")
    pcall(nginx_signals.stop(conf))
    log.verbose("stopped services")
    error(err) -- report to main error handler
  end
end

local lapp = [[
Usage: kong start [OPTIONS]

Start Kong (Nginx and other configured services) in the configured
prefix directory.

Options:
 -c,--conf           (optional string) configuration file
 -p,--prefix         (optional string) prefix at which Kong should be running
 --nginx-conf        (optional string) custom Nginx configuration template
 --no-migrations                       disable migrations on the DB
]]

return {
  lapp = lapp,
  execute = execute
}
