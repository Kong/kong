-- Send signals to the `nginx` executable
-- @see http://nginx.org/en/docs/beginners_guide.html#control

local IO = require "kong.tools.io"
local cutils = require "kong.cli.utils"
local constants = require "kong.constants"

-- Cache config path, parsed config and DAO factory
local kong_config_path
local kong_config
local dao_factory

local KONG_SYSLOG = "kong-hf.mashape.com"

-- Retrieve the desired Kong config file, parse it and provides a DAO factory
-- Will cache them for future retrieval
-- @param args_config Path to the desired configuration (usually from the --config CLI argument)
-- @return Path to desired Kong config
-- @return Parsed desired Kong configuration
-- @return Instanciated DAO factory
local function get_kong_config_path(args_config)
  -- Get configuration from default or given path
  if not kong_config_path then
    kong_config_path = cutils.get_kong_config_path(args_config)
  end
  if not kong_config then
    kong_config, dao_factory = IO.load_configuration_and_dao(kong_config_path)
  end
  return kong_config_path, kong_config, dao_factory
end

-- Check if an executable (typically `nginx`) is a distribution of openresty
-- @param path_to_check Path to the binary
-- @return true or false
local function is_openresty(path_to_check)
  local cmd = path_to_check.." -v 2>&1"
  local handle = io.popen(cmd)
  local out = handle:read()
  handle:close()
  return out:match("^nginx version: ngx_openresty/") or out:match("^nginx version: openresty/")
end

-- Find an `nginx` executable in defined paths
-- @return Path to found executable or nil if none was found
local function find_nginx()
  local nginx_bin = "nginx"
  local nginx_search_paths = {
    "/usr/local/openresty/nginx/sbin/",
    "/usr/local/opt/openresty/bin/",
    "/usr/local/bin/",
    "/usr/sbin/",
    ""
  }

  for i = 1, #nginx_search_paths do
    local prefix = nginx_search_paths[i]
    local to_check = prefix..nginx_bin
    if is_openresty(to_check) then
      return to_check
    end
  end
end

-- Prepare the nginx `--prefix` directory (working directory)
-- Extract the nginx config from a Kong config file into an `nginx.conf` file
-- @param args_config Path to the desired configuration (usually from the --config CLI argument)
local function prepare_nginx_working_dir(args_config)
  local _, kong_config = get_kong_config_path(args_config)

  if kong_config.send_anonymous_reports then
    -- If there is no internet connection, disable this feature
    local socket = require "socket"
    if socket.dns.toip(KONG_SYSLOG) then
      kong_config.nginx = "error_log syslog:server="..KONG_SYSLOG..":61828 error;\n"..kong_config.nginx
    else
      cutils.logger:warn("The internet connection might not be available, cannot resolve "..KONG_SYSLOG)
    end
  end

  -- Create nginx folder if needed
  local _, err = IO.path:mkdir(IO.path:join(kong_config.nginx_working_dir, "logs"))
  if err then
    cutils.logger:error_exit(err)
  end

  os.execute("touch "..IO.path:join(kong_config.nginx_working_dir, "logs", "error.log"))
  os.execute("touch "..IO.path:join(kong_config.nginx_working_dir, "logs", "access.log"))

  -- Extract nginx config to nginx folder
  local ok, err = IO.write_to_file(IO.path:join(kong_config.nginx_working_dir, constants.CLI.NGINX_CONFIG), kong_config.nginx)
  if not ok then
    cutils.logger:error_exit(err)
  end
end

-- Prepare the database keyspace if needed (run schema migrations)
-- @param args_config Path to the desired configuration (usually from the --config CLI argument)
local function prepare_database(args_config)
  local _, _, dao_factory = get_kong_config_path(args_config)

  -- Migrate the DB if needed and possible
  local keyspace, err = dao_factory:get_migrations()
  if err then
    cutils.logger:error_exit(err)
  elseif keyspace == nil then
    cutils.logger:log("Database not initialized. Running migrations...")
    local migrations = require("kong.tools.migrations")(dao_factory, cutils.get_luarocks_install_dir())
    migrations:migrate(function(migration, err)
      if err then
        cutils.logger:error_exit(err)
      elseif migration then
        cutils.logger:success("Migrated up to: "..cutils.colors.yellow(migration.name))
      end
    end)
  end
end

local _M = {}

function _M.prepare_kong(args_config)
  prepare_nginx_working_dir(args_config)
  prepare_database(args_config)
end

-- Send a signal to `nginx`. No signal will start the process
-- This function wraps the control of the `nginx` execution.
-- @see http://nginx.org/en/docs/beginners_guide.html#control
-- @param args_config Path to the desired configuration (usually from the --config CLI argument)
-- @param signal Signal to send. Ignoring this argument will try to start `nginx`
-- @return A boolean: true for success, false otherwise
function _M.send_signal(args_config, signal)
  -- Make sure nginx is there and is openresty
  local nginx_path = find_nginx()
  if not nginx_path then
    cutils.logger:error_exit("can't find nginx")
  end

  local kong_config_path, kong_config = get_kong_config_path(args_config)

  -- Build nginx signal command
  local cmd = string.format("KONG_CONF=%s %s -p %s -c %s -g 'pid %s;' %s",
                            kong_config_path,
                            nginx_path,
                            kong_config.nginx_working_dir,
                            constants.CLI.NGINX_CONFIG,
                            constants.CLI.NGINX_PID,
                            signal ~= nil and "-s "..signal or "")

  return os.execute(cmd) == 0
end

-- Wrapper around a stop signal, testing if Kong is already running
-- @param args_config Path to the desired configuration (usually from the --config CLI argument)
function _M.is_running(args_config)
  -- Get configuration from default or given path
  local _, kong_config = get_kong_config_path(args_config)

  local pid = IO.path:join(kong_config.nginx_working_dir, constants.CLI.NGINX_PID)

  if not IO.file_exists(pid) then
    cutils.logger:error_exit("Not running. Could not find pid at: "..pid)
  end
end

return _M
