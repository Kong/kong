-- Send signals to the `nginx` executable
-- Run necessary
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
-- @return Parsed desired Kong configuration
-- @return Path to desired Kong config
-- @return Instanciated DAO factory
local function get_kong_config(args_config)
  -- Get configuration from default or given path
  if not kong_config_path then
    kong_config_path = cutils.get_kong_config_path(args_config)
    cutils.logger:info("Using configuration: "..kong_config_path)
  end
  if not kong_config then
    kong_config, dao_factory = IO.load_configuration_and_dao(kong_config_path)
  end
  return kong_config, kong_config_path, dao_factory
end

-- Check if an executable (typically `nginx`) is a distribution of openresty
-- @param path_to_check Path to the binary
-- @return true or false
local function is_openresty(path_to_check)
  if IO.file_exists(path_to_check) then
    local cmd = path_to_check.." -v"
    local out, code = IO.os_execute(cmd)
    if code ~= 0 then
      cutils.logger:error_exit(out)
    end
    return out:match("^nginx version: ngx_openresty/")
        or out:match("^nginx version: openresty/")
        or out:match("^nginx version: nginx/[%w.%s]+%(nginx%-plus%-extras.+%)")
  end
  return false
end

-- Paths where to search for an `nginx` executable in addition to the usual $PATH
local NGINX_BIN = "nginx"
local NGINX_SEARCH_PATHS = {
  "/usr/local/openresty/nginx/sbin/",
  "/usr/local/opt/openresty/bin/",
  "/usr/local/bin/",
  "/usr/sbin/"
}

-- Try to find an `nginx` executable in defined paths, or in $PATH
-- @return Path to found executable or nil if none was found
local function find_nginx()
  for i = 1, #NGINX_SEARCH_PATHS + 1 do
    local prefix = NGINX_SEARCH_PATHS[i] and NGINX_SEARCH_PATHS[i] or ""
    local to_check = prefix..NGINX_BIN
    if is_openresty(to_check) then
      return to_check
    end
  end
end

-- Prepare the nginx `--prefix` directory (working directory)
-- Extract the nginx config from a Kong config file into an `nginx.conf` file
-- @param args_config Path to the desired configuration (usually from the --config CLI argument)
local function prepare_nginx_working_dir(args_config)
  local kong_config = get_kong_config(args_config)

  -- Create nginx folder if needed
  local _, err = IO.path:mkdir(IO.path:join(kong_config.nginx_working_dir, "logs"))
  if err then
    cutils.logger:error_exit(err)
  end

  os.execute("touch "..IO.path:join(kong_config.nginx_working_dir, "logs", "error.log"))
  os.execute("touch "..IO.path:join(kong_config.nginx_working_dir, "logs", "access.log"))

  -- Extract nginx config from kong config, replace any needed value
  local nginx_config = kong_config.nginx
  local nginx_inject = {
    proxy_port = kong_config.proxy_port,
    admin_port = kong_config.admin_port
  }

  -- Inject properties
  for k, v in pairs(nginx_inject) do
    nginx_config = nginx_config:gsub("{{"..k.."}}", v)
  end

  -- Inject additional configurations
  nginx_inject = {
    nginx_plus_status = kong_config.nginx_plus_status and "location /status { status; }" or nil
  }

  for _, v in pairs(nginx_inject) do
    nginx_config = nginx_config:gsub("# {{additional_configuration}}", "# {{additional_configuration}}\n    "..v)
  end

  -- Inject anonymous reports
  if kong_config.send_anonymous_reports then
    -- If there is no internet connection, disable this feature
    local socket = require "socket"
    if socket.dns.toip(KONG_SYSLOG) then
      nginx_config = "error_log syslog:server="..KONG_SYSLOG..":61828 error;\n"..nginx_config
    else
      cutils.logger:warn("The internet connection might not be available, cannot resolve "..KONG_SYSLOG)
    end
  end

  -- Write nginx config
  local ok, err = IO.write_to_file(IO.path:join(kong_config.nginx_working_dir, constants.CLI.NGINX_CONFIG), nginx_config)
  if not ok then
    cutils.logger:error_exit(err)
  end
end

-- Prepare the database keyspace if needed (run schema migrations)
-- @param args_config Path to the desired configuration (usually from the --config CLI argument)
local function prepare_database(args_config)
  local kong_config, _, dao_factory = get_kong_config(args_config)

  -- Migrate the DB if needed and possible
  local keyspace, err = dao_factory:get_migrations()
  if err then
    cutils.logger:error_exit(err)
  elseif keyspace == nil then
    cutils.logger:info("Database not initialized. Running migrations...")
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

-- Prettifies table properties in a nice human readable way
-- @return The prettified string
local function prettify_table_properties(t)
  local result = ""
  for k, v in pairs(t) do
    result = result..k.."="..v.." "
  end
  return result == "" and result or result:sub(1, string.len(result) - 1)
end

local _M = {}

function _M.prepare_kong(args_config)
  local kong_config, kong_config_path = get_kong_config(args_config)

  -- Print important informations
  cutils.logger:info(string.format([[Proxy port...%s
       API port.....%s
       Database.....%s %s
  ]],
  kong_config.proxy_port,
  kong_config.admin_port,
  kong_config.database,
  prettify_table_properties(kong_config.databases_available[kong_config.database].properties)))

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
    cutils.logger:error_exit(string.format("Kong cannot find an 'nginx' executable.\nMake sure it is in your $PATH or in one of the following directories:\n%s", table.concat(NGINX_SEARCH_PATHS, "\n")))
  end

  local kong_config, kong_config_path = get_kong_config(args_config)

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
  local kong_config = get_kong_config(args_config)

  local pid_file = IO.path:join(kong_config.nginx_working_dir, constants.CLI.NGINX_PID)

  if IO.file_exists(pid_file) then
    local pid = IO.read_file(pid_file)
    if os.execute("kill -0 "..pid) == 0 then
      return true
    else
      cutils.logger:info("Removing pid at: "..pid_file)
      local _, err = os.remove(pid_file)
      if err then
        error(err)
      end
      return false, "Not running. Could not find pid: "..pid
    end
  else
    return false, "Not running. Could not find pid at: "..pid_file
  end
end

return _M
