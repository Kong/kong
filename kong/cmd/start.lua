local migrations_utils = require "kong.cmd.utils.migrations"
local prefix_handler = require "kong.cmd.utils.prefix_handler"
local nginx_signals = require "kong.cmd.utils.nginx_signals"
local conf_loader = require "kong.conf_loader"
local kong_global = require "kong.global"
local kill = require "kong.cmd.utils.kill"
local log = require "kong.cmd.utils.log"
local DB = require "kong.db"
local lfs = require "lfs"


local function is_socket(path)
  return lfs.attributes(path, "mode") == "socket"
end

local function cleanup_dangling_unix_sockets(socket_path)
  local found = {}

  for child in lfs.dir(socket_path) do
    local path = socket_path .. "/" .. child
    if is_socket(path) then
      table.insert(found, path)
    end
  end

  if #found < 1 then
    return
  end

  log.warn("Found dangling unix sockets in the prefix directory (%q) while " ..
           "preparing to start Kong. This may be a sign that Kong was " ..
           "previously shut down uncleanly or is in an unknown state and " ..
           "could require further investigation.",
           socket_path)

  log.warn("Attempting to remove dangling sockets before starting Kong...")

  for _, sock in ipairs(found) do
    if is_socket(sock) then
      log.warn("removing unix socket: %s", sock)
      assert(os.remove(sock))
    end
  end
end

local function execute(args)
  args.db_timeout = args.db_timeout and (args.db_timeout * 1000) or nil
  args.lock_timeout = args.lock_timeout

  local conf = assert(conf_loader(args.conf, {
    prefix = args.prefix
  }, { starting = true }))

  conf.pg_timeout = args.db_timeout or conf.pg_timeout -- connect + send + read

  assert(not kill.is_running(conf.nginx_pid),
         "Kong is already running in " .. conf.prefix)

  assert(prefix_handler.prepare_prefix(conf, args.nginx_conf, nil, nil,
         args.nginx_conf_flags))

  cleanup_dangling_unix_sockets(conf.socket_path)

  _G.kong = kong_global.new()
  kong_global.init_pdk(_G.kong, conf)

  local db = assert(DB.new(conf))
  assert(db:init_connector())

  local schema_state = assert(db:schema_state())
  local err

  xpcall(function()
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
    pcall(nginx_signals.stop, conf)
    log.verbose("stopped services")
    error(err) -- report to main error handler
  end
end

local lapp = [[
Usage: kong start [OPTIONS]

Start Kong (Nginx and other configured services) in the configured
prefix directory.

Options:
 -c,--conf                 (optional string)   Configuration file.

 -p,--prefix               (optional string)   Override prefix directory.

 --nginx-conf              (optional string)   Custom Nginx configuration template.

 --run-migrations          (optional boolean)  Run migrations before starting.

 --db-timeout              (optional number)   Timeout, in seconds, for all database
                                               operations.

 --lock-timeout            (default 60)        When --run-migrations is enabled, timeout,
                                               in seconds, for nodes waiting on the
                                               leader node to finish running migrations.

 --nginx-conf-flags        (optional string)   Flags that can be used to control
                                               how Nginx configuration templates are rendered
]]

return {
  lapp = lapp,
  execute = execute
}
