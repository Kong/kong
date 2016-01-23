local logger = require "kong.cli.utils.logger"
local IO = require "kong.tools.io"
local dao_loader = require "kong.tools.dao_loader"

local _M = {}

_M.STATUSES = {
  ALL_RUNNING = "ALL_RUNNING",
  SOME_RUNNING = "SOME_RUNNING",
  NOT_RUNNINT = "NOT_RUNNING"
}

-- Services ordered by priority
local services = {
  require "kong.cli.services.dnsmasq",
  require "kong.cli.services.serf",
  require "kong.cli.services.nginx"
}

local function prepare_database(configuration)
  setmetatable(configuration.dao_config, require "kong.tools.printable")
  logger:info(string.format([[database...........%s %s]], configuration.database, tostring(configuration.dao_config)))

  local dao_factory = dao_loader.load(configuration)
  local migrations = require("kong.dao.migrations")(dao_factory, configuration)

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

local function prepare_working_dir(configuration)
  local working_dir = configuration.nginx_working_dir

  -- Check if the folder exists
  if not IO.file_exists(working_dir) then
    logger:info("Creating working directory at "..working_dir)
    local _, exit_code = IO.os_execute("mkdir -p "..working_dir)
    if exit_code ~= 0 then
      return false, "Cannot create the working directory at "..working_dir
    end
  end

  logger:info("Setting working directory to "..working_dir)

  -- Check if it's a folder
  local _, exit_code = IO.os_execute("[[ -d "..working_dir.." ]]")
  if exit_code ~= 0 then
    return false, "The working directory must point to a directory and not to a file"
  end

  -- Check if we can read in the folder
  local _, exit_code = IO.os_execute("[[ -r "..working_dir.." ]]")
  if exit_code ~= 0 then
    return false, "The working directory must have read permissions"
  end

  -- Check if we can write in the folder
  local _, exit_code = IO.os_execute("[[ -w "..working_dir.." ]]")
  if exit_code ~= 0 then
    return false, "The working directory must have write permissions"
  end

  -- Check if we can execute in the folder
  local _, exit_code = IO.os_execute("[[ -x "..working_dir.." ]]")
  if exit_code ~= 0 then
    return false, "The working directory must have executable permissions"
  end
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
  -- Backwards
  for i=#services, 1, -1 do
    services[i](configuration, configuration_path):stop()
  end
end

function _M.start_all(configuration, configuration_path)
  -- Prepare and check working directory
  local _, err = prepare_working_dir(configuration)
  if err then
    return false, err
  end

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
