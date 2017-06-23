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

  if args.migrate_timeout then
    assert(not args.run_migrations, "only one of the options " ..
           "`--run-migrations` or `--migrate-timeout` can be specified")
    assert(args.migrate_timeout > 0, "the migrate-timeout must be greater " ..
           "than 0")
  end

  assert(not kill.is_running(conf.nginx_pid),
         "Kong is already running in " .. conf.prefix)

  local err
  local dao = assert(DAOFactory.new(conf))
  xpcall(function()
    assert(prefix_handler.prepare_prefix(conf, args.nginx_conf))
    if not args.migrate_timeout and 
       (args.run_migrations or not dao.db:migrations_initialized()) then
      assert(dao:run_migrations())
    end
    if args.migrate_timeout then
      local expire = ngx.now() + args.migrate_timeout
      local ok, err = dao:are_migrations_uptodate()
      log.verbose("waiting for migrations to complete...")
      while not ok and expire >= ngx.now() do
        ngx.sleep(1)  -- very arbitrary value ...
        ok, err = dao:are_migrations_uptodate()
      end
      assert(ok, "migration timeout: " .. err)
    else
      assert(dao:are_migrations_uptodate())
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
 -c,--conf         (optional string)   configuration file
 -p,--prefix       (optional string)   override prefix directory
 --nginx-conf      (optional string)   custom Nginx configuration template
 --run-migrations  (optional boolean)  optionally run migrations on the DB
 --migrate-timeout (optional number)   how long to wait for migrations to be
                                       completed by another node
 
]]

return {
  lapp = lapp,
  execute = execute
}
