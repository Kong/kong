local kong_nginx_template = require "kong.templates.nginx_kong"
local nginx_template = require "kong.templates.nginx"
local pl_template = require "pl.template"
local pl_stringx = require "pl.stringx"
local pl_tablex = require "pl.tablex"
local pl_utils = require "pl.utils"
local pl_file = require "pl.file"
local pl_path = require "pl.path"
local pl_dir = require "pl.dir"
local socket = require "socket"
local utils = require "kong.tools.utils"
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
client:connect('%s', %d) \
client:request { \
  method = 'POST', \
  path = '/cluster/events/', \
  body = [=[${PAYLOAD}]=], \
  headers = { \
    ['content-type'] = 'application/json' \
  } \
}"

resty -e "$CMD"
]]

local function gen_default_ssl_cert(kong_config)
  -- create SSL folder
  local ok, err = pl_dir.makepath(pl_path.join(kong_config.prefix, "ssl"))
  if not ok then return nil, err end

  local ssl_cert = kong_config.ssl_cert_default
  local ssl_cert_key = kong_config.ssl_cert_key_default
  local ssl_cert_csr = kong_config.ssl_cert_csr_default

  if not pl_path.exists(ssl_cert) and not pl_path.exists(ssl_cert_key) then
    log.verbose("auto-generating default SSL certificate and key...")

    local passphrase = utils.random_string()
    local commands = {
      fmt("openssl genrsa -des3 -out %s -passout pass:%s 1024", ssl_cert_key, passphrase),
      fmt("openssl req -new -key %s -out %s -subj \"/C=US/ST=California/L=San Francisco/O=Kong/OU=IT Department/CN=localhost\" -passin pass:%s", ssl_cert_key, ssl_cert_csr, passphrase),
      fmt("cp %s %s.org", ssl_cert_key, ssl_cert_key),
      fmt("openssl rsa -in %s.org -out %s -passin pass:%s", ssl_cert_key, ssl_cert_key, passphrase),
      fmt("openssl x509 -req -in %s -signkey %s -out %s", ssl_cert_csr, ssl_cert_key, ssl_cert),
      fmt("rm %s", ssl_cert_csr),
      fmt("rm %s.org", ssl_cert_key)
    }
    for i = 1, #commands do
      local ok, _, _, stderr = pl_utils.executeex(commands[i])
      if not ok then
        return nil, "could not generate default SSL certificate: "..stderr
      end
    end
  else
    log.verbose("default SSL certificate found at %s", ssl_cert)
  end

  return true
end

local function get_ulimit()
  local ok, _, stdout, stderr = pl_utils.executeex "ulimit -n"
  if not ok then return nil, stderr end
  return tonumber(pl_stringx.strip(stdout))
end

local function gather_system_infos(compile_env)
  local infos = {}

  local ulimit, err = get_ulimit()
  if not ulimit then return nil, err end
  infos.worker_rlimit = ulimit
  infos.worker_connections = math.min(16384, ulimit)

  return infos
end

local function compile_conf(kong_config, conf_template, env_t)
  env_t = env_t or {}

  -- computed config properties for templating
  local compile_env = {
    _escape = ">",
    pairs = pairs,
    tostring = tostring
  }

  if kong_config.cassandra_ssl and kong_config.cassandra_ssl_trusted_cert then
    compile_env["lua_ssl_trusted_certificate"] = kong_config.cassandra_ssl_trusted_cert
  end
  if kong_config.dnsmasq then
    compile_env["dns_resolver"] = "127.0.0.1:"..kong_config.dnsmasq_port
  end

  local infos, err = gather_system_infos()
  if not infos then return nil, err end
  if kong_config.nginx_optimizations then
    compile_env = pl_tablex.merge(compile_env, infos,  true) -- union
  end

  if kong_config.anonymous_reports then
    -- If there is no internet connection, disable this feature
    if socket.dns.toip(constants.SYSLOG.ADDRESS) then
      compile_env["syslog_reports"] = fmt("error_log syslog:server=%s:%d error;", 
                                                    constants.SYSLOG.ADDRESS, 
                                                    constants.SYSLOG.PORT)
    end
  end

  compile_env = pl_tablex.merge(compile_env, kong_config, true) -- union
  compile_env = pl_tablex.merge(compile_env, env_t, true) -- union

  local post_template = pl_template.substitute(conf_template, compile_env)
  return string.gsub(post_template, "(${%b{}})", function(w)
    local name = w:sub(4, -3)
    return compile_env[name:lower()]
  end)
end

local function compile_kong_conf(kong_config, env_t)
  return compile_conf(kong_config, kong_nginx_template, env_t)
end

local function compile_nginx_conf(kong_config)
  return compile_conf(kong_config, nginx_template)
end

local function prepare_prefix(kong_config)
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

  -- create log files in case
  local ok, _, _, stderr = pl_utils.executeex("touch "..kong_config.nginx_err_logs)
  if not ok then return nil, stderr end
  local ok, _, _, stderr = pl_utils.executeex("touch "..kong_config.nginx_acc_logs)
  if not ok then return nil, stderr end

  log.verbose("saving Serf identifier in %s", kong_config.serf_node_id)
  if not pl_path.exists(kong_config.serf_node_id) then
    local id = utils.get_hostname().."_"..kong_config.cluster_listen.."_"..utils.random_string()
    pl_file.write(kong_config.serf_node_id, id)
  end

  log.verbose("saving Serf shell script handler in %s", kong_config.serf_event)
  local script = fmt(script_template, "127.0.0.1", kong_config.admin_port)
  pl_file.write(kong_config.serf_event, script)
  local ok, _, _, stderr = pl_utils.executeex("chmod +x "..kong_config.serf_event)
  if not ok then return nil, stderr end

  local ssl_cert
  local ssl_cert_key
  if kong_config.ssl then
    ssl_cert = kong_config.ssl_cert
    ssl_cert_key = kong_config.ssl_cert_key
    if not ssl_cert and not ssl_cert_key then
      -- must generate default cert
      local ok, err = gen_default_ssl_cert(kong_config)
      if not ok then return nil, err end
      ssl_cert = kong_config.ssl_cert_default
      ssl_cert_key = kong_config.ssl_cert_key_default
    end
  end

  -- check ulimit
  local ulimit, err = get_ulimit()
  if not ulimit then return nil, err end
  if ulimit < 4096 then
    log.warn([[ulimit is currently set to "%d". For better performance set it to at least "4096" using "ulimit -n"]], ulimit)
  end

  -- write NGINX conf
  local nginx_conf, err = compile_nginx_conf(kong_config)
  if not nginx_conf then return nil, err end
  pl_file.write(kong_config.nginx_conf, nginx_conf)

  -- write Kong's NGINX conf
  local kong_nginx_conf, err = compile_kong_conf(kong_config, {
    ssl_cert = ssl_cert,
    ssl_cert_key = ssl_cert_key
  })
  if not kong_nginx_conf then return nil, err end
  pl_file.write(kong_config.nginx_kong_conf, kong_nginx_conf)

  -- write kong.conf in prefix (for workers and CLI)
  local buf = {}
  for k, v in pairs(kong_config) do
    if type(v) == "table" then
      v = table.concat(v, ",")
    end
    if v ~= "" then
      buf[#buf+1] = k.." = "..tostring(v)
    end
  end
  pl_file.write(kong_config.kong_conf, table.concat(buf, "\n"))

  return true
end

return {
  gen_default_ssl_cert = gen_default_ssl_cert,
  compile_nginx_conf = compile_nginx_conf,
  compile_kong_conf = compile_kong_conf,
  prepare_prefix = prepare_prefix
}
