-- Send signals to the `nginx` executable
-- Run the necessary so the nginx working dir (prefix) and database are correctly prepared
-- @see http://nginx.org/en/docs/beginners_guide.html#control

local IO = require "kong.tools.io"
local utils = require "kong.tools.utils"
local cutils = require "kong.cli.utils"
local ssl = require "kong.cli.utils.ssl"
local constants = require "kong.constants"
local syslog = require "kong.tools.syslog"
local socket = require "socket"
local dnsmasq = require "kong.cli.utils.dnsmasq"
local stringy = require "stringy"

-- Cache config path, parsed config and DAO factory
local kong_config_path
local kong_config
local dao_factory

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
  local env_path_variable = os.getenv("PATH")
  local env_paths = {}
  if env_path_variable and stringy.strip(env_path_variable) ~= "" then
    env_paths = stringy.split(env_path_variable, ":")
  end

  local search_paths = utils.table_merge(env_paths, NGINX_SEARCH_PATHS)

  for _, v in ipairs(search_paths) do
    local prefix = stringy.endswith(v, "/") and v or v.."/"
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
  -- Create logs files
  os.execute("touch "..IO.path:join(kong_config.nginx_working_dir, "logs", "error.log"))
  os.execute("touch "..IO.path:join(kong_config.nginx_working_dir, "logs", "access.log"))
  -- Create SSL folder if needed
  local _, err = IO.path:mkdir(IO.path:join(kong_config.nginx_working_dir, "ssl"))
  if err then
    cutils.logger:error_exit(err)
  end
  -- TODO: this is NOT the place to do this.
  -- @see https://github.com/Mashape/kong/issues/92 for configuration validation/defaults
  -- @see https://github.com/Mashape/kong/issues/217 for a better configuration file

  -- Check memory cache
  if kong_config.memory_cache_size then
    if tonumber(kong_config.memory_cache_size) == nil then
      cutils.logger:error_exit("Invalid \"memory_cache_size\" setting")
    elseif tonumber(kong_config.memory_cache_size) < 32 then
      cutils.logger:error_exit("Invalid \"memory_cache_size\" setting: needs to be at least 32")
    end
  else
    kong_config.memory_cache_size = 128 -- Default value
    cutils.logger:warn("Setting \"memory_cache_size\" to default 128MB")
  end

  ssl.prepare_ssl(kong_config)
  local ssl_cert_path, ssl_key_path = ssl.get_ssl_cert_and_key(kong_config)
  local trusted_ssl_cert_path = kong_config.databases_available[kong_config.database].properties.ssl_certificate -- DAO ssl cert

  -- Extract nginx config from kong config, replace any needed value
  local nginx_config = kong_config.nginx
  local nginx_inject = {
    proxy_port = kong_config.proxy_port,
    proxy_ssl_port = kong_config.proxy_ssl_port,
    admin_api_port = kong_config.admin_api_port,
    dns_resolver = "127.0.0.1:"..kong_config.dnsmasq_port,
    memory_cache_size = kong_config.memory_cache_size,
    ssl_cert = ssl_cert_path,
    ssl_key = ssl_key_path,
    lua_ssl_trusted_certificate = trusted_ssl_cert_path ~= nil and "lua_ssl_trusted_certificate \""..trusted_ssl_cert_path.."\";" or ""
  }

  -- Auto-tune
  local res, code = IO.os_execute("ulimit -n")
  if code == 0 then
    nginx_inject.auto_worker_rlimit_nofile = res
    nginx_inject.auto_worker_connections = tonumber(res) > 16384 and 16384 or res
  else
    cutils.logger:error_exit("Can't determine ulimit")
  end

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
    if socket.dns.toip(constants.SYSLOG.ADDRESS) then
      nginx_config = "error_log syslog:server="..constants.SYSLOG.ADDRESS..":"..tostring(constants.SYSLOG.PORT).." error;\n"..nginx_config
    else
      cutils.logger:warn("The internet connection might not be available, cannot resolve "..constants.SYSLOG.ADDRESS)
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
  local migrations = require("kong.tools.migrations")(dao_factory)

  local keyspace_exists, err = dao_factory.migrations:keyspace_exists()
  if err then
    cutils.logger:error_exit(err)
  elseif not keyspace_exists then
    cutils.logger:info("Database not initialized. Running migrations...")
  end

  local err = migrations:migrate_all(kong_config, function(identifier, migration)
    if migration then
      cutils.logger:success(string.format("%s migrated up to: %s", identifier, cutils.colors.yellow(migration.name)))
    end
  end)
  if err then
    cutils.logger:error_exit(err)
  end
end

--
-- PUBLIC
--

local _M = {}

-- Constants
local START = "start"
local RESTART = "restart"
local RELOAD = "reload"
local STOP = "stop"
local QUIT = "quit"

_M.RELOAD = RELOAD
_M.STOP = STOP
_M.QUIT = QUIT

function _M.prepare_kong(args_config, signal)
  local kong_config = get_kong_config(args_config)
  local dao_config = kong_config.databases_available[kong_config.database].properties

  local printable_mt = require "kong.tools.printable"
  setmetatable(dao_config, printable_mt)

  -- Print important informations
  cutils.logger:info(string.format([[Kong version.......%s
       Proxy HTTP port....%s
       Proxy HTTPS port...%s
       Admin API port.....%s
       dnsmasq port.......%s
       Database...........%s %s
  ]],
  constants.VERSION,
  kong_config.proxy_port,
  kong_config.proxy_ssl_port,
  kong_config.admin_api_port,
  kong_config.dnsmasq_port,
  kong_config.database,
  tostring(dao_config)))

  cutils.logger:info("Connecting to the database...")
  prepare_database(args_config)
  prepare_nginx_working_dir(args_config, signal)
end

local function check_port(port)
  if cutils.is_port_open(port) then
    cutils.logger:error_exit("Port "..tostring(port).." is already being used by another process.")
  end
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
  if not signal then signal = START end

  if signal == START then
    local ports = { kong_config.proxy_port, kong_config.proxy_ssl_port, kong_config.admin_api_port }
    for _,port in ipairs(ports) do
      check_port(port)
    end
  end

  -- Build nginx signal command
  local cmd = string.format("KONG_CONF=%s %s -p %s -c %s -g 'pid %s;' %s",
                            kong_config_path,
                            nginx_path,
                            kong_config.nginx_working_dir,
                            constants.CLI.NGINX_CONFIG,
                            constants.CLI.NGINX_PID,
                            signal == START and "" or "-s "..signal)

  -- dnsmasq start/stop
  if signal == START then
    dnsmasq.stop(kong_config)
    check_port(kong_config.dnsmasq_port)
    dnsmasq.start(kong_config)
  elseif signal == STOP or signal == QUIT then
    dnsmasq.stop(kong_config)
  end

  -- Check ulimit value
  if signal == START or signal == RESTART or signal == RELOAD then
    local res, code = IO.os_execute("ulimit -n")
    if code == 0 and tonumber(res) < 4096 then
      cutils.logger:warn("ulimit is currently set to \""..res.."\". For better performance set it to at least \"4096\" using \"ulimit -n\"")
    end
  end

  -- Report signal action
  if kong_config.send_anonymous_reports then
    syslog.log({signal=signal})
  end

  -- Start failure handler
  local success = os.execute(cmd) == 0

  if signal == START and not success then
    dnsmasq.stop(kong_config) -- If the start failed, then stop dnsmasq
  end

  if signal == STOP and success then
    if IO.file_exists(kong_config.pid_file) then
      os.execute("while [ -f "..kong_config.pid_file.." ]; do sleep 0.5; done")
    end
  end

  return success
end

-- Test if Kong is already running by detecting a pid file.
--
-- Note:
-- If the pid file exists but no process seem to be running, will assume the pid
-- is obsolete and try to delete it.
--
-- @param args_config Path to the desired configuration (usually from the --config CLI argument)
-- @return true is running, false otherwise
-- @return If not running, an error containing the path where the pid was supposed to be
function _M.is_running(args_config)
  -- Get configuration from default or given path
  local kong_config = get_kong_config(args_config)

  if IO.file_exists(kong_config.pid_file) then
    local pid = IO.read_file(kong_config.pid_file)
    local _, code = IO.os_execute("kill -0 "..pid)
    if code == 0 then
      return true
    else
      cutils.logger:warn("It seems like Kong crashed the last time it was started!")
      cutils.logger:info("Removing pid at: "..kong_config.pid_file)
      local _, err = os.remove(kong_config.pid_file)
      if err then
        error(err)
      end
      return false, "Not running. Could not find pid: "..pid
    end
  else
    return false, "Not running. Could not find pid at: "..kong_config.pid_file
  end
end

return _M
