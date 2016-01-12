-- Send signals to the `nginx` executable
-- Run the necessary so the nginx working dir (prefix) and database are correctly prepared
-- @see http://nginx.org/en/docs/beginners_guide.html#control

local IO = require "kong.tools.io"
local cutils = require "kong.cli.utils"
local ssl = require "kong.cli.utils.ssl"
local constants = require "kong.constants"
local syslog = require "kong.tools.syslog"
local socket = require "socket"
local dnsmasq = require "kong.cli.utils.dnsmasq"
local config = require "kong.tools.config_loader"
local dao = require "kong.tools.dao_loader"

-- Cache config path, parsed config and DAO factory
local kong_config_path, kong_config

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
    kong_config = config.load(kong_config_path)
  end
  return kong_config, kong_config_path
end

-- Check if an executable (typically `nginx`) is a distribution of openresty
-- @param path_to_check Path to the binary
-- @return true or false
local function is_openresty(path_to_check)
  local cmd = path_to_check.." -v"
  local out = IO.os_execute(cmd)
  return out:match("^nginx version: ngx_openresty/")
      or out:match("^nginx version: openresty/")
      or out:match("^nginx version: nginx/[%w.%s]+%(nginx%-plus%-extras.+%)")
end

-- Preferred paths where to search for an `nginx` executable in priority to the $PATH
local NGINX_BIN = "nginx"
local NGINX_SEARCH_PATHS = {
  "/usr/local/openresty/nginx/sbin/",
  "/usr/local/opt/openresty/bin/",
  "/usr/local/bin/",
  "/usr/sbin/",
  "" -- to check the $PATH
}

-- Try to find an `nginx` executable in defined paths, or in $PATH
-- @return Path to found executable or nil if none was found
local function find_nginx()
  for i = 1, #NGINX_SEARCH_PATHS do
    local prefix = NGINX_SEARCH_PATHS[i]
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

  ssl.prepare_ssl(kong_config)
  local ssl_cert_path, ssl_key_path = ssl.get_ssl_cert_and_key(kong_config)
  local trusted_ssl_cert_path = kong_config.dao_config.ssl_certificate -- DAO ssl cert

  -- Extract nginx config from kong config, replace any needed value
  local nginx_config = kong_config.nginx
  local nginx_inject = {
    proxy_port = kong_config.proxy_port,
    proxy_ssl_port = kong_config.proxy_ssl_port,
    admin_api_port = kong_config.admin_api_port,
    dns_resolver = kong_config.dns_resolver.address,
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
  local kong_config = get_kong_config(args_config)
  local dao_factory = dao.load(kong_config)
  local migrations = require("kong.tools.migrations")(dao_factory, kong_config)

  local keyspace_exists, err = dao_factory.migrations:keyspace_exists()
  if err then
    cutils.logger:error_exit(err)
  elseif not keyspace_exists then
    cutils.logger:info("Database not initialized. Running migrations...")
  end

  local function before(identifier)
    cutils.logger:info(string.format(
      "Migrating %s on keyspace \"%s\" (%s)",
      cutils.colors.yellow(identifier),
      cutils.colors.yellow(dao_factory.properties.keyspace),
      dao_factory.type
    ))
  end

  local function on_each_success(identifier, migration)
    cutils.logger:info(string.format(
      "%s migrated up to: %s",
      identifier,
      cutils.colors.yellow(migration.name)
    ))
  end

  local err = migrations:run_all_migrations(before, on_each_success)
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
  local dao_config = kong_config.dao_config

  local printable_mt = require "kong.tools.printable"
  setmetatable(dao_config, printable_mt)

  -- Print important informations
  cutils.logger:info(string.format([[Kong version.......%s
       Proxy HTTP port....%s
       Proxy HTTPS port...%s
       Admin API port.....%s
       DNS resolver.......%s
       Database...........%s %s
  ]],
  constants.VERSION,
  kong_config.proxy_port,
  kong_config.proxy_ssl_port,
  kong_config.admin_api_port,
  kong_config.dns_resolver.address,
  kong_config.database,
  tostring(dao_config)))

  cutils.logger:info("Connecting to the database...")
  prepare_database(args_config)
  prepare_nginx_working_dir(args_config, signal)
end

-- Checks whether a port is available. Exits the application if not available.
-- @param port The port to check
-- @param name Functional name the port is used for (display name)
-- @param timeout (optional) Timeout in seconds after which a failure is logged
-- and application exit is performed, if not provided then it will fail at once without retries.
local function check_port(port, name, timeout)
  local expire = socket.gettime() + (timeout or 0)
  local msg = tostring(port) .. (name and " ("..tostring(name)..")")
  local warned
  while not cutils.is_port_bindable(port) do
    if expire <= socket.gettime() then
      cutils.logger:error_exit("Port "..msg.." is being blocked by another process.")
    else
      if not warned then
        cutils.logger:warn("Port "..msg.." is unavailable, retrying for "..tostring(timeout).." seconds")
        warned = true
      end
    end
    socket.sleep(0.5)
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
  local port_timeout = 1   -- OPT: make timeout configurable (note: this is a blocking timeout!)
  local nginx_path = find_nginx()
  if not nginx_path then
    cutils.logger:error_exit(string.format("Kong cannot find an 'nginx' executable.\nMake sure it is in your $PATH or in one of the following directories:\n%s", table.concat(NGINX_SEARCH_PATHS, "\n")))
  end

  local kong_config, kong_config_path = get_kong_config(args_config)
  if not signal then signal = START end

  if signal == START then
    local ports = {
      ["Kong proxy"] = kong_config.proxy_port,
      ["Kong proxy ssl"] = kong_config.proxy_ssl_port,
      ["Kong admin api"] = kong_config.admin_api_port
    }
    for name, port in pairs(ports) do
      check_port(port, name, port_timeout)
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
    if kong_config.dns_resolver.dnsmasq then
      local dnsmasq_port = kong_config.dns_resolver.port
      check_port(dnsmasq_port, "dnsmasq", port_timeout)
      dnsmasq.start(kong_config.nginx_working_dir, dnsmasq_port)
    end
  elseif signal == STOP or signal == QUIT then
    dnsmasq.stop(kong_config)
  end

  -- Check ulimit value
  if signal == START or signal == RESTART or signal == RELOAD then
    local res, code = IO.os_execute("ulimit -n")
    if code == 0 and tonumber(res) < 4096 then
      cutils.logger:warn('ulimit is currently set to "'..res..'". For better performance set it to at least "4096" using "ulimit -n"')
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
