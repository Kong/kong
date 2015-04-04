local IO = require "kong.tools.io"
local cutils = require "kong.cli.utils"
local constants = require "kong.constants"

local _M = {}

local KONG_SYSLOG = "kong-hf.mashape.com"

local function is_openresty(path_to_check)
  local cmd = tostring(path_to_check).." -v 2>&1"
  local handle = io.popen(cmd)
  local out = handle:read()
  handle:close()
  local matched = out:match("^nginx version: ngx_openresty/") or out:match("^nginx version: openresty/")
  if matched then
    return path_to_check
  end
end

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
    local to_check = tostring(prefix)..tostring(nginx_bin)
    if is_openresty(to_check) then
      return to_check
    end
  end
end

local function prepare_nginx_working_dir(kong_config)
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
    error(err)
  end

  return kong_config.nginx_working_dir
end

function _M.start(args_config)
  -- Make sure nginx is there and is openresty
  local nginx_path = find_nginx()
  if not nginx_path then
    cutils.logger:error_exit("can't find nginx")
  end

  -- Get configuration from default or given path
  local config_path = cutils.get_kong_config_path(args_config)
  local config, dao_factory = IO.load_configuration_and_dao(config_path)

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

  -- Prepare nginx --prefix dir
  local nginx_working_dir = prepare_nginx_working_dir(config)

  -- Build nginx start command
  local cmd = string.format("KONG_CONF=%s %s -p %s -c %s -g 'pid %s;'",
                            config_path,
                            nginx_path,
                            nginx_working_dir,
                            constants.CLI.NGINX_CONFIG,
                            constants.CLI.NGINX_PID)

  if os.execute(cmd) == 0 then
    cutils.logger:success("Started")
  else
    cutils.logger:error_exit("Could not start Kong")
  end

end

return _M.start
