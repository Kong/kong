local default_nginx_template = require "kong.templates.nginx"
local kong_nginx_template = require "kong.templates.nginx_kong"
local pl_template = require "pl.template"
local pl_stringx = require "pl.stringx"
local pl_tablex = require "pl.tablex"
local pl_utils = require "pl.utils"
local pl_file = require "pl.file"
local pl_path = require "pl.path"
local version = require "version"
local pl_dir = require "pl.dir"
local socket = require "socket"
local utils = require "kong.tools.utils"
local meta = require "kong.meta"
local log = require "kong.cmd.utils.log"
local constants = require "kong.constants"
local fmt = string.format

-- script from old services.serf module
local script_template = [[
#!/bin/sh

PAYLOAD=`cat` # Read from stdin
if [ "$SERF_EVENT" != "user" ]; then
  PAYLOAD="{\"type\":\"${SERF_EVENT}\",\"entity\": \"${PAYLOAD}\"}"
fi

CMD="\
local http = require 'resty.http' \
local client = http.new() \
client:set_timeout(5000) \
client:connect('%s', %d) \
client:request { \
  method = 'POST', \
  path = '/cluster/events/', \
  body = [=[${PAYLOAD}]=], \
  headers = { \
    ['content-type'] = 'application/json' \
  } \
}"

%s -e "$CMD"
]]

local resty_bin_name = "resty"
local resty_version_pattern = "nginx[^\n]-openresty[^\n]-([%d%.]+)"
local resty_compatible = version.set(unpack(meta._DEPENDENCIES.nginx))
local resty_search_paths = {
  "/usr/local/openresty/bin",
  ""
}

local function is_openresty(bin_path)
  local cmd = fmt("%s -V", bin_path)
  local ok, _, _, stderr = pl_utils.executeex(cmd)
  local lines = pl_stringx.splitlines(stderr)
  if #lines > 1 then
    stderr = lines[2] -- show openresty version line
  else
    stderr = lines[1] -- strip trailing line jump
  end
  log.debug("%s: '%s'", cmd, stderr)
  if ok and stderr then
    local version_match = stderr:match(resty_version_pattern)
    if not version_match or not resty_compatible:matches(version_match) then
      log.verbose("'resty' found at %s uses incompatible OpenResty. Kong "..
                  "requires OpenResty version %s, got %s", bin_path,
                  tostring(resty_compatible), version_match)
      return false
    end
    return true
  end
  log.debug("OpenResty 'resty' executable not found at %s", bin_path)
end

local function find_resty_bin()
  log.debug("searching for OpenResty 'resty' executable")

  local found
  for _, path in ipairs(resty_search_paths) do
    local path_to_check = pl_path.join(path, resty_bin_name)
    if is_openresty(path_to_check) then
      found = path_to_check
      log.debug("found OpenResty 'resty' executable at %s", found)
      break
    end
  end

  if not found then
    return nil, ("could not find OpenResty 'resty' executable. Kong requires"..
                 " version %s"):format(tostring(resty_compatible))
  end

  return found
end

local function gen_default_ssl_cert(kong_config, admin)
  -- create SSL folder
  local ok, err = pl_dir.makepath(pl_path.join(kong_config.prefix, "ssl"))
  if not ok then return nil, err end

  local ssl_cert, ssl_cert_key, ssl_cert_csr
  if admin then
    ssl_cert = kong_config.admin_ssl_cert_default
    ssl_cert_key = kong_config.admin_ssl_cert_key_default
    ssl_cert_csr = kong_config.admin_ssl_cert_csr_default
  else
    ssl_cert = kong_config.ssl_cert_default
    ssl_cert_key = kong_config.ssl_cert_key_default
    ssl_cert_csr = kong_config.ssl_cert_csr_default
  end

  if not pl_path.exists(ssl_cert) and not pl_path.exists(ssl_cert_key) then
    log.verbose("generating %s SSL certificate and key",
                     admin and "admin" or "default")

    local passphrase = utils.random_string()
    local commands = {
      fmt("openssl genrsa -des3 -out %s -passout pass:%s 2048", ssl_cert_key, passphrase),
      fmt("openssl req -new -key %s -out %s -subj \"/C=US/ST=California/L=San Francisco/O=Kong/OU=IT Department/CN=localhost\" -passin pass:%s -sha256", ssl_cert_key, ssl_cert_csr, passphrase),
      fmt("cp %s %s.org", ssl_cert_key, ssl_cert_key),
      fmt("openssl rsa -in %s.org -out %s -passin pass:%s", ssl_cert_key, ssl_cert_key, passphrase),
      fmt("openssl x509 -req -in %s -signkey %s -out %s -sha256", ssl_cert_csr, ssl_cert_key, ssl_cert),
      fmt("rm %s", ssl_cert_csr),
      fmt("rm %s.org", ssl_cert_key)
    }
    for i = 1, #commands do
      local ok, _, _, stderr = pl_utils.executeex(commands[i])
      if not ok then
        return nil, "could not generate "..(admin and "admin" or "default").." SSL certificate: "..stderr
      end
    end
  else
    log.verbose("%s SSL certificate found at %s",
                     admin and "admin" or "default", ssl_cert)
  end

  return true
end

local function get_ulimit()
  local ok, _, stdout, stderr = pl_utils.executeex "ulimit -n"
  if not ok then return nil, stderr end
  local sanitized_limit = pl_stringx.strip(stdout)
  if sanitized_limit:lower():match("unlimited") then
    return 65536
  else
    return tonumber(sanitized_limit)
  end
end

local function gather_system_infos(compile_env)
  local infos = {}

  local ulimit, err = get_ulimit()
  if not ulimit then return nil, err end

  infos.worker_rlimit = ulimit
  infos.worker_connections = math.min(16384, ulimit)

  return infos
end

local function compile_conf(kong_config, conf_template)
  -- computed config properties for templating
  local compile_env = {
    _escape = ">",
    pairs = pairs,
    tostring = tostring
  }

  if kong_config.anonymous_reports and socket.dns.toip(constants.REPORTS.ADDRESS) then
    compile_env["syslog_reports"] = fmt("error_log syslog:server=%s:%d error;",
                                        constants.REPORTS.ADDRESS, constants.REPORTS.SYSLOG_PORT)
  end
  if kong_config.nginx_optimizations then
    local infos, err = gather_system_infos()
    if not infos then return nil, err end
    compile_env = pl_tablex.merge(compile_env, infos,  true) -- union
  end

  compile_env = pl_tablex.merge(compile_env, kong_config, true) -- union
  compile_env.dns_resolver = table.concat(compile_env.dns_resolver, " ")

  local post_template = pl_template.substitute(conf_template, compile_env)
  return string.gsub(post_template, "(${%b{}})", function(w)
    local name = w:sub(4, -3)
    return compile_env[name:lower()] or ""
  end)
end

local function compile_kong_conf(kong_config)
  return compile_conf(kong_config, kong_nginx_template)
end

local function compile_nginx_conf(kong_config, template)
  template = template or default_nginx_template
  return compile_conf(kong_config, template)
end

local function prepare_prefix(kong_config, nginx_custom_template_path)
  log.verbose("preparing nginx prefix directory at %s", kong_config.prefix)

  if not pl_path.exists(kong_config.prefix) then
    log("prefix directory %s not found, trying to create it", kong_config.prefix)
    local ok, err = pl_dir.makepath(kong_config.prefix)
    if not ok then return nil, err end
  elseif not pl_path.isdir(kong_config.prefix) then
    return nil, kong_config.prefix.." is not a directory"
  end

  -- create directories in prefix
  for _, dir in ipairs {"logs", "serf", "pids"} do
    local ok, err = pl_dir.makepath(pl_path.join(kong_config.prefix, dir))
    if not ok then return nil, err end
  end

  -- create log files in case they don't already exist
  if not pl_path.exists(kong_config.nginx_err_logs) then
    local ok, err = pl_file.write(kong_config.nginx_err_logs, "")
    if not ok then return nil, err end
  end
  if not pl_path.exists(kong_config.nginx_acc_logs) then
    local ok, err = pl_file.write(kong_config.nginx_acc_logs, "")
    if not ok then return nil, err end
  end
  if not pl_path.exists(kong_config.nginx_admin_acc_logs) then
    local ok, err = pl_file.write(kong_config.nginx_admin_acc_logs, "")
    if not ok then return nil, err end
  end

  log.verbose("saving serf identifier to %s", kong_config.serf_node_id)
  if not pl_path.exists(kong_config.serf_node_id) then
    local id = utils.get_hostname().."_"..kong_config.cluster_listen.."_"..utils.random_string()
    pl_file.write(kong_config.serf_node_id, id)
  end

  local resty_bin, err = find_resty_bin()
  if not resty_bin then return nil, err end

  log.verbose("saving serf shell script handler to %s", kong_config.serf_event)
  -- setting serf admin ip
  local admin_ip = kong_config.admin_ip
  if kong_config.admin_ip == "0.0.0.0" then
    admin_ip = "127.0.0.1"
  end
  -- saving serf script handler
  local script = fmt(script_template, admin_ip, kong_config.admin_port, resty_bin)
  pl_file.write(kong_config.serf_event, script)
  local ok, _, _, stderr = pl_utils.executeex("chmod +x "..kong_config.serf_event)
  if not ok then return nil, stderr end

  -- generate default SSL certs if needed
  if kong_config.ssl and not kong_config.ssl_cert and not kong_config.ssl_cert_key then
    log.verbose("SSL enabled, no custom certificate set: using default certificate")
    local ok, err = gen_default_ssl_cert(kong_config)
    if not ok then return nil, err end
    kong_config.ssl_cert = kong_config.ssl_cert_default
    kong_config.ssl_cert_key = kong_config.ssl_cert_key_default
  end
  if kong_config.admin_ssl and not kong_config.admin_ssl_cert and not kong_config.admin_ssl_cert_key then
    log.verbose("Admin SSL enabled, no custom certificate set: using default certificate")
    local ok, err = gen_default_ssl_cert(kong_config, true)
    if not ok then return nil, err end
    kong_config.admin_ssl_cert = kong_config.admin_ssl_cert_default
    kong_config.admin_ssl_cert_key = kong_config.admin_ssl_cert_key_default
  end

  -- check ulimit
  local ulimit, err = get_ulimit()
  if not ulimit then return nil, err
  elseif ulimit < 4096 then
    log.warn([[ulimit is currently set to "%d". For better performance set it]]
           ..[[ to at least "4096" using "ulimit -n"]], ulimit)
  end

  -- compile Nginx configurations
  local nginx_template
  if nginx_custom_template_path then
    if not pl_path.exists(nginx_custom_template_path) then
      return nil, "no such file: "..nginx_custom_template_path
    end
    nginx_template = pl_file.read(nginx_custom_template_path)
  end

  -- write NGINX conf
  local nginx_conf, err = compile_nginx_conf(kong_config, nginx_template)
  if not nginx_conf then return nil, err end
  pl_file.write(kong_config.nginx_conf, nginx_conf)

  -- write Kong's NGINX conf
  local nginx_kong_conf, err = compile_kong_conf(kong_config)
  if not nginx_kong_conf then return nil, err end
  pl_file.write(kong_config.nginx_kong_conf, nginx_kong_conf)

  -- write kong.conf in prefix (for workers and CLI)
  local buf = {
    "# *************************",
    "# * DO NOT EDIT THIS FILE *",
    "# *************************",
    "# This configuration file is auto-generated. If you want to modify",
    "# the Kong configuration please edit/create the original `kong.conf`",
    "# file. Any modifications made here will be lost.",
    "# Start Kong with `--vv` to show where it is looking for that file.",
    "",
  }

  for k, v in pairs(kong_config) do
    if type(v) == "table" then
      v = table.concat(v, ",")
    end
    if v ~= "" then
      buf[#buf+1] = k.." = "..tostring(v)
    end
  end

  pl_file.write(kong_config.kong_env, table.concat(buf, "\n"))

  return true
end

return {
  prepare_prefix = prepare_prefix,
  compile_kong_conf = compile_kong_conf,
  compile_nginx_conf = compile_nginx_conf,
  gen_default_ssl_cert = gen_default_ssl_cert
}
