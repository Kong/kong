local kong_nginx_template = require "kong.templates.nginx_kong"
local nginx_template = require "kong.templates.nginx"
local pl_template = require "pl.template"
local pl_stringx = require "pl.stringx"
local pl_tablex = require "pl.tablex"
local pl_utils = require "pl.utils"
local pl_file = require "pl.file"
local pl_path = require "pl.path"
local pl_dir = require "pl.dir"
local utils = require "kong.tools.utils"
local ssl = require "kong.cmd.utils.ssl"
local log = require "kong.cmd.utils.log"

local serf_node_id = "serf.id"

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

local function gather_system_infos(compile_env)
  local infos = {}

  local ok, _, stdout, stderr = pl_utils.executeex "ulimit -n"
  if not ok then return nil, stderr end
  infos.ulimit = pl_stringx.strip(stdout)

  return infos
end

local function compile_conf(kong_config, conf_template)
  -- computed config properties for templating
  local compile_env = {
    _escape = ">",
    pairs = pairs,
    tostring = tostring,
    nginx_vars = {}
  }

  local ssl_data, err = ssl.get_ssl_cert_and_key(kong_config, kong_config.prefix)
  if not ssl_data then return nil, err end

  if kong_config.cassandra_ssl and kong_config.cassandra_ssl_trusted_cert then
    compile_env["lua_ssl_trusted_certificate"] = kong_config.cassandra_ssl_trusted_cert
  end

  if kong_config.ssl then
    compile_env["ssl_cert"] = ssl_data.ssl_cert
    compile_env["ssl_cert_key"] = ssl_data.ssl_cert_key
  end

  if kong_config.dnsmasq then
    compile_env["dns_resolver"] = "127.0.0.1:"..kong_config.dnsmasq_port
  end

  if kong_config.nginx_optimizations then
    local infos, err = gather_system_infos()
    if not infos then return nil, err end
    compile_env = pl_tablex.merge(compile_env, infos,  true) -- union
  end

  compile_env = pl_tablex.merge(compile_env, kong_config, true) -- union

  local post_template = pl_template.substitute(conf_template, compile_env)
  return string.gsub(post_template, "(${%b{}})", function(w)
    local name = w:sub(4, -3)
    return compile_env[name:lower()]
  end)
end

local function compile_kong_conf(kong_config)
  return compile_conf(kong_config, kong_nginx_template)
end

local function compile_nginx_conf(kong_config)
  return compile_conf(kong_config, nginx_template)
end

local function touch(file_path)
  return pl_utils.executeex("touch "..file_path)
end

local function prepare_prefix(kong_config, nginx_prefix)
  log.verbose("preparing nginx prefix directory at %s", nginx_prefix)

  if not pl_path.exists(nginx_prefix) then
    log("prefix directory %s not found, trying to create it", nginx_prefix)
    local ok, err = pl_dir.makepath(nginx_prefix)
    if not ok then return nil, err end
  elseif not pl_path.isdir(nginx_prefix) then
    return nil, nginx_prefix.." is not a directory"
  end

  -- create log dir in case
  local logs_path = pl_path.join(nginx_prefix, "logs")
  local ok, err = pl_dir.makepath(logs_path)
  if not ok then return nil, err end

  -- create log files in case
  local err_logs_path = pl_path.join(logs_path, "error.log")
  local acc_logs_path = pl_path.join(logs_path, "access.log")

  local ok, _, _, stderr = touch(err_logs_path)
  if not ok then return nil, stderr end
  local ok, _, _, stderr = touch(acc_logs_path)
  if not ok then return nil, stderr end

  -- pids folder
  local pids_path = pl_path.join(nginx_prefix, "pids")
  local ok, err = pl_dir.makepath(pids_path)
  if not ok then return nil, err end

  -- serf folder (node identifier + shell script)
  local serf_path = pl_path.join(nginx_prefix, "serf")
  local ok, err = pl_dir.makepath(serf_path)
  if not ok then return nil, err end

  local id_path = pl_path.join(nginx_prefix, "serf", serf_node_id)
  log.verbose("saving Serf identifier in %s", id_path)
  if not pl_path.exists(id_path) then
    local id = utils.get_hostname().."_"..kong_config.cluster_listen.."_"..utils.random_string()
    pl_file.write(id_path, id)
  end

  local script_path = pl_path.join(nginx_prefix, "serf", "serf_event.sh")
  log.verbose("saving Serf shell script handler in %s", script_path)
  local script = string.format(script_template, "127.0.0.1", kong_config.admin_port)

  pl_file.write(script_path, script)

  local ok, _, _, stderr = pl_utils.executeex("chmod +x "..script_path)
  if not ok then return nil, stderr end

  -- auto-generate default SSL certificate
  local ok, err = ssl.prepare_ssl_cert_and_key(nginx_prefix)
  if not ok then return nil, err end

  local kong_conf_path = pl_path.join(nginx_prefix, "kong.conf")
  local nginx_conf_path = pl_path.join(nginx_prefix, "nginx.conf")
  local kong_nginx_conf_path = pl_path.join(nginx_prefix, "nginx-kong.conf")

  -- write NGINX conf
  local nginx_conf, err = compile_nginx_conf(kong_config)
  if not nginx_conf then return nil, err end

  pl_file.write(nginx_conf_path, nginx_conf)

  -- write Kong's NGINX conf
  local kong_nginx_conf, err = compile_kong_conf(kong_config)
  if not kong_nginx_conf then return nil, err end
  pl_file.write(kong_nginx_conf_path, kong_nginx_conf)

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
  pl_file.write(kong_conf_path, table.concat(buf, "\n"))

  return true
end

return {
  compile_nginx_conf = compile_nginx_conf,
  compile_kong_conf = compile_kong_conf,
  prepare_prefix = prepare_prefix
}
