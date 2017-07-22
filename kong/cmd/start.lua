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

    if args.run_migrations then
      assert(dao:run_migrations())
    end

    local ok, err = dao:are_migrations_uptodate()
    if err then
      -- error correctly formatted by the DAO
      error(err)
    end

    if not ok then
      -- we cannot start, throw a very descriptive error to instruct the user
      error("the current database schema does not match\n"                  ..
            "this version of Kong.\n\nPlease run `kong migrations up` "     ..
            "first to update/initialise the database schema.\nBe aware "    ..
            "that Kong migrations should only run from a single node, and " ..
            "that nodes\nrunning migrations concurrently will conflict "    ..
            "with each other and might corrupt\nyour database schema!")
    end

    ok, err = dao:check_schema_consensus()
    if err then
      -- error correctly formatted by the DAO
      error(err)
    end

    if not ok then
      error("Cassandra has not reached cluster consensus yet")
    end

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
 -c,--conf        (optional string)   configuration file
 -p,--prefix      (optional string)   override prefix directory
 --nginx-conf     (optional string)   custom Nginx configuration template
 --run-migrations (optional boolean)  optionally run migrations on the DB
]]

return {
  lapp = lapp,
  execute = execute
}
