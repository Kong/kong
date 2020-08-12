local migrations_utils = require "kong.cmd.utils.migrations"
local prefix_handler = require "kong.cmd.utils.prefix_handler"
local nginx_signals = require "kong.cmd.utils.nginx_signals"
local conf_loader = require "kong.conf_loader"
local kong_global = require "kong.global"
local kill = require "kong.cmd.utils.kill"
local log = require "kong.cmd.utils.log"
local DB = require "kong.db"

local fmt = string.format

local function to_set(l)
  local set = {}
  for _, v in ipairs(l) do
    set[v]=true
  end
  return set
end

local function list_fields(db, tname)

  local qs = {
    postgres = fmt("SELECT column_name FROM information_schema.columns WHERE table_schema='%s' and table_name='%s';",
      db.connector.config.schema,
      tname),
    cassandra = fmt("SELECT column_name FROM system_schema.columns WHERE keyspace_name='%s' and table_name='%s';",
      db.connector.keyspace,
      tname)
  }

  if not qs[db.strategy] then
    return {}
  end

  local fields = {}
  local rows, err = db.connector:query(qs[db.strategy])

  if err then
    return nil, err, err_t
  end
  for _, v in ipairs(rows) do
    local kk,vv = next(v)
    fields[vv]=true
  end

  return fields
end

local function has_ws_id_in_db(db, tname)
  return list_fields(db, tname).ws_id
end

local function custom_wspaced_entities(db, conf)
  local res = {}

  local connector = db.connector
  local strategy = db.strategy
  db.plugins:load_plugin_schemas(conf.loaded_plugins)

  for k, v in pairs(db.daos) do
    local schema = v.schema
    if schema.workspaceable and
    not has_ws_id_in_db(db, schema.name) then -- we have to check at db level
      local unique = {}

      for field_name, field_schema in pairs(schema.fields) do
        if field_schema.unique then
          unique[field_name] = field_schema
        end
      end

      if next(unique) then
        res[k]= {
          primary_key = schema.primary_key[1],
          primary_keys = to_set(schema.primary_key),
          unique_keys = unique
        }
      end
    end
  end

  local driver
  if strategy == 'postgres' then
    driver = db.connector
    _=_
  elseif strategy == 'cassandra' then
    mig_helper.seed_strategies.c.coordinator = db.connector:connect_migrations()
    driver = db.connector
  else
    print("dbless")
    return false
  end

  local ret = {}
  for k, v in pairs(res) do
    table.insert(ret, k)
  end

  return #ret>0 and ret
end

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

    local non_migrated_entities = custom_wspaced_entities(db, conf)
    if non_migrated_entities then
      log.info(table.concat(
        {"This instance contains workspaced entities that need a custom migration.",
         "please use the provided helpers to migrate them: ", unpack(require("pl.tablex").values(non_migrated_entities))
        }, "\n"))
      error()
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
