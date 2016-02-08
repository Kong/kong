local BaseService = require "kong.cli.services.base_service"
local IO = require "kong.tools.io"
local logger = require "kong.cli.utils.logger"
local ssl = require "kong.cli.utils.ssl"
local constants = require "kong.constants"
local syslog = require "kong.tools.syslog"
local socket = require "socket"

local Nginx = BaseService:extend()

local SERVICE_NAME = "nginx"
local START = "start"
local RELOAD = "reload"
local STOP = "stop"
local QUIT = "quit"

local function prepare_folders(configuration)
  -- Create nginx folder if needed
  local _, err = IO.path:mkdir(IO.path:join(configuration.nginx_working_dir, "logs"))
  if err then
    return false, err
  end

  -- Create logs files
  os.execute("touch "..IO.path:join(configuration.nginx_working_dir, "logs", "error.log"))
  os.execute("touch "..IO.path:join(configuration.nginx_working_dir, "logs", "access.log"))

  -- Create SSL folder if needed
  local _, err = IO.path:mkdir(IO.path:join(configuration.nginx_working_dir, "ssl"))
  if err then
    return false, err
  end

  return true
end

local function prepare_ssl_certificates(configuration)
  local _, err = ssl.prepare_ssl(configuration)
  if err then
    return false, err
  end

  local res, err = ssl.get_ssl_cert_and_key(configuration)
  if err then
    return false, err
  end

  local trusted_ssl_cert_path = configuration.dao_config.ssl and
                                configuration.dao_config.ssl.certificate_authority or nil

  return {
    ssl_cert_path = res.ssl_cert_path,
    ssl_key_path = res.ssl_key_path,
    trusted_ssl_cert_path = trusted_ssl_cert_path
  }
end

local function get_current_user()
  return IO.os_execute("whoami")
end

local function get_primary_group(user)
  return IO.os_execute("id -g -n "..user)
end

local function is_root()
  local _, exit_code = IO.os_execute("[[ $EUID -eq 0 ]]")
  return exit_code == 0
end

local function prepare_nginx_configuration(configuration, ssl_config)

  local current_user = get_current_user()

  -- Extract nginx config from kong config, replace any needed value
  local nginx_config = configuration.nginx
  local nginx_inject = {
    user = is_root() and "user "..current_user.." "..get_primary_group(current_user)..";" or "",
    proxy_listen = configuration.proxy_listen,
    proxy_listen_ssl = configuration.proxy_listen_ssl,
    admin_api_listen = configuration.admin_api_listen,
    dns_resolver = configuration.dns_resolver.address,
    memory_cache_size = configuration.memory_cache_size,
    ssl_cert = ssl_config.ssl_cert_path,
    ssl_key = ssl_config.ssl_key_path,
    lua_ssl_trusted_certificate = ssl_config.trusted_ssl_cert_path and
                                  'lua_ssl_trusted_certificate "'..configuration.dao_config.ssl.certificate_authority..'";' or ""
  }

  -- Auto-tune
  local res, code = IO.os_execute("ulimit -n")
  if code == 0 then
    nginx_inject.auto_worker_rlimit_nofile = res
    nginx_inject.auto_worker_connections = tonumber(res) > 16384 and 16384 or res
  else
    return false, "Can't determine ulimit"
  end

  -- Inject properties
  for k, v in pairs(nginx_inject) do
    nginx_config = nginx_config:gsub("{{"..k.."}}", v)
  end

  -- Inject anonymous reports
  if configuration.send_anonymous_reports then
    -- If there is no internet connection, disable this feature
    if socket.dns.toip(constants.SYSLOG.ADDRESS) then
      nginx_config = "error_log syslog:server="..constants.SYSLOG.ADDRESS..":"..tostring(constants.SYSLOG.PORT).." error;\n"..nginx_config
    else
      logger:warn("The internet connection might not be available, cannot resolve "..constants.SYSLOG.ADDRESS)
    end
  end

  -- Write nginx config
  local ok, err = IO.write_to_file(IO.path:join(configuration.nginx_working_dir, constants.CLI.NGINX_CONFIG), nginx_config)
  if not ok then
    return false, err
  end
end

function Nginx:new(configuration, configuration_path)
  self._configuration = configuration
  self._configuration_path = configuration_path

  Nginx.super.new(self, SERVICE_NAME, self._configuration.nginx_working_dir)
end

function Nginx:prepare()
  -- Create working directory if missing
  local ok, err = Nginx.super.prepare(self, self._configuration.nginx_working_dir)
  if not ok then
    return nil, err
  end

  -- Preparing nginx folders
  local _, err = prepare_folders(self._configuration)
  if err then
    return false, err
  end

  -- Preparing SSL certificates
  local res, err = prepare_ssl_certificates(self._configuration)
  if err then
    return false, err
  end

  -- Preparing the Nginx configuration file
  local _, err = prepare_nginx_configuration(self._configuration, res)
  if err then
    return false, err
  end

  return true
end

function Nginx:_invoke_signal(cmd, signal)
  local full_nginx_cmd = string.format("KONG_CONF=%s %s -p %s -c %s -g 'pid %s;' %s",
                            self._configuration_path,
                            cmd,
                            self._configuration.nginx_working_dir,
                            constants.CLI.NGINX_CONFIG,
                            self._pid_file_path,
                            signal == START and "" or "-s "..signal)

  -- Check ulimit value
  if signal == START or signal == RELOAD then
    local res, code = IO.os_execute("ulimit -n")
    if code == 0 and tonumber(res) < 4096 then
      logger:warn("ulimit is currently set to \""..res.."\". For better performance set it to at least \"4096\" using \"ulimit -n\"")
    end
  end

  -- Report signal action
  if self._configuration.send_anonymous_reports then
    syslog.log({signal=signal})
  end

  -- Start failure handler
  local res, code = IO.os_execute(full_nginx_cmd)
  if code == 0 then
    return true
  else
    return false, res
  end
end

function Nginx:_get_cmd()
  local cmd, err = Nginx.super._get_cmd(self, {
    "/usr/local/openresty/nginx/sbin/",
    "/usr/local/opt/openresty/bin/",
    "/usr/local/bin/",
    "/usr/sbin/"
  }, function(path)
    local res, code = IO.os_execute(path.." -v")
    if code == 0 then
      return res:match("^nginx version: ngx_openresty/") or
             res:match("^nginx version: openresty/")
    end

    return false
  end)

  return cmd, err
end

function Nginx:start()
  if self:is_running() then
    return nil, SERVICE_NAME.." is already running"
  end

  local cmd, err = self:_get_cmd()
  if err then
    return nil, err
  end

  local ok, err = self:_invoke_signal(cmd, START)
  if ok then
    local listen_addresses = {
      proxy_listen = self._configuration.proxy_listen,
      proxy_listen_ssl = self._configuration.proxy_listen_ssl,
      admin_api_listen = self._configuration.admin_api_listen
    }
    setmetatable(listen_addresses, require "kong.tools.printable")
    logger:info(string.format([[nginx .............%s]], tostring(listen_addresses)))
  end

  return ok, err
end

function Nginx:stop()
  local cmd, err = self:_get_cmd()
  if err then
    return nil, err
  end

  local _, err = self:_invoke_signal(cmd, STOP)
  if not err then
    os.execute("while [ -f "..self._pid_file_path.." ]; do sleep 0.5; done")
  end
end

function Nginx:reload()
  local cmd, err = self:_get_cmd()
  if err then
    return nil, err
  end

  return self:_invoke_signal(cmd, RELOAD)
end

function Nginx:quit()
  local cmd, err = self:_get_cmd()
  if err then
    return nil, err
  end

  return self:_invoke_signal(cmd, QUIT)
end

return Nginx
