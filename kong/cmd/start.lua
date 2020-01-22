local migrations_utils = require "kong.cmd.utils.migrations"
local prefix_handler = require "kong.cmd.utils.prefix_handler"
local nginx_signals = require "kong.cmd.utils.nginx_signals"
local conf_loader = require "kong.conf_loader"
local kong_global = require "kong.global"
local kill = require "kong.cmd.utils.kill"
local log = require "kong.cmd.utils.log"
local DB = require "kong.db"


local function execute(args)
  args.db_timeout = args.db_timeout * 1000
  args.lock_timeout = args.lock_timeout

  local conf = assert(conf_loader(args.conf, {
    prefix = args.prefix
  }, { starting = true }))

  conf.pg_timeout = args.db_timeout -- connect + send + read

  conf.cassandra_timeout = args.db_timeout -- connect + send + read
  conf.cassandra_schema_consensus_timeout = args.db_timeout

  assert(not kill.is_running(conf.nginx_pid),
         "Kong is already running in " .. conf.prefix)

  _G.kong = kong_global.new()
  kong_global.init_pdk(_G.kong, conf, nil) -- nil: latest PDK

  local db = assert(DB.new(conf))
  assert(db:init_connector())

  local schema_state = assert(db:schema_state())
  local err

  xpcall(function()
    assert(prefix_handler.prepare_prefix(conf, args.nginx_conf))

    if not schema_state:is_up_to_date() and args.run_migrations then
      migrations_utils.up(schema_state, db, {
        ttl = args.lock_timeout,
      })

      schema_state = assert(db:schema_state())
    end

    migrations_utils.check_state(schema_state)

    if schema_state.missing_migrations or schema_state.pending_migrations then
      local r = ""
      if schema_state.missing_migrations then
        log.info("Database is missing some migrations:\n%s",
                 tostring(schema_state.missing_migrations))

        r = "\n\n"
      end

      if schema_state.pending_migrations then
        log.info("%sDatabase has pending migrations:\n%s",
                 r, tostring(schema_state.pending_migrations))
      end
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
 -c,--conf        (optional string)   Configuration file.

 -p,--prefix      (optional string)   Override prefix directory.

 --nginx-conf     (optional string)   Custom Nginx configuration template.

 --run-migrations (optional boolean)  Run migrations before starting.

 --db-timeout     (default 60)        Timeout, in seconds, for all database
                                      operations (including schema consensus for
                                      Cassandra).

 --lock-timeout   (default 60)        When --run-migrations is enabled, timeout,
                                      in seconds, for nodes waiting on the
                                      leader node to finish running migrations.
]]

return {
  lapp = lapp,
  execute = execute
}
