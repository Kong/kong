local logger = require "kong.cli.utils.logger"
local dao = require "kong.tools.dao_loader"

local _M = {}

_M.STATUSES = { 
  ALL_RUNNING = "ALL_RUNNING",
  SOME_RUNNING = "SOME_RUNNING",
  NOT_RUNNINT = "NOT_RUNNING"
}

-- Services ordered by priority
local services = {
  require "kong.cli.services.dnsmasq",
  require "kong.cli.services.nginx",
  require "kong.cli.services.serf"
}

local function prepare_database(configuration)
  setmetatable(configuration.dao_config, require "kong.tools.printable")
  logger:info(string.format([[database...........%s %s]], configuration.database, tostring(configuration.dao_config)))

  local dao_factory = dao.load(configuration)
  local migrations = require("kong.tools.migrations")(dao_factory, configuration)

  local keyspace_exists, err = dao_factory.migrations:keyspace_exists()
  if err then
    return false, err
  elseif not keyspace_exists then
    logger:info("Database not initialized. Running migrations...")
  end

  local function before(identifier)
    logger:info(string.format(
      "Migrating %s on keyspace \"%s\" (%s)",
      logger.colors.yellow(identifier),
      logger.colors.yellow(dao_factory.properties.keyspace),
      dao_factory.type
    ))
  end

  local function on_each_success(identifier, migration)
    logger:info(string.format(
      "%s migrated up to: %s",
      identifier,
      logger.colors.yellow(migration.name)
    ))
  end

  local err = migrations:run_all_migrations(before, on_each_success)
  if err then
    return false, err
  end

  return true
end

function _M.check_status(configuration, configuration_path)
  local running, not_running

  for index, service in ipairs(services) do
    if service(configuration, configuration_path):is_running() then
      running = true
    else
      not_running = true
    end
  end

  if running and not not_running then
    return _M.STATUSES.ALL_RUNNING
  elseif not_running and not running then
    return _M.STATUSES.NOT_RUNNING
  else
    return _M.STATUSES.SOME_RUNNING
  end
end

function _M.stop_all(configuration, configuration_path)
  for _, service in ipairs(services) do
    service(configuration, configuration_path):stop()
  end
end

function _M.start_all(configuration, configuration_path)
  -- Prepare database if not initialized yet
  local _, err = prepare_database(configuration)
  if err then
    return false, err
  end

  for _, v in ipairs(services) do
    local obj = v(configuration, configuration_path)
    obj:prepare()
    local ok, err = obj:start()
    if not ok then
      return ok, err
    end
  end

  return true
end

return _M