local NGINX_VARS = {
  prefix = true,
  plugins = true,
  cluster_listen = true,
  cluster_listen_rpc = true,
  database = true,
  pg_host = true,
  pg_port = true,
  pg_user = true,
  pg_password = true,
  pg_database = true,
  cassandra_contact_points = true,
  cassandra_keyspace = true,
  cassandra_timeout = true,
  cassandra_consistency = true,
  cassandra_ssl = true,
  cassandra_ssl_verify = true,
  cassandra_username = true,
  cassandra_password = true,
  anonymous_reports = true
}

local kong_nginx_template = require "kong.templates.nginx_kong"
local nginx_template = require "kong.templates.nginx"
local pl_template = require "pl.template"
local pl_stringx = require "pl.stringx"
local pl_pretty = require "pl.pretty"
local pl_tablex = require "pl.tablex"
local pl_utils = require "pl.utils"
local pl_file = require "pl.file"
local pl_path = require "pl.path"
local pl_dir = require "pl.dir"
local ssl = require "kong.cmd.utils.ssl"
local log = require "kong.cmd.utils.log"
local fmt = string.format

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

  -- variables needed in Nginx
  for k in pairs(NGINX_VARS) do
    local v = kong_config[k]
    local typ = type(v)
    if typ == "table" then
      v = pl_pretty.write(v, string.rep(" ", 6), true)
    elseif typ == "string" then
      v = string.format("%q", v)
    end

    compile_env.nginx_vars[k] = v
  end

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
    log.verbose(fmt("prefix directory %s not found, trying to create it", nginx_prefix))
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

  -- auto-generate default SSL certificate
  local ok, err = ssl.prepare_ssl_cert_and_key(nginx_prefix)
  if not ok then return nil, err end

  local nginx_config_path = pl_path.join(nginx_prefix, "nginx.conf")
  local kong_nginx_conf_path = pl_path.join(nginx_prefix, "nginx-kong.conf")

  -- write NGINX conf
  local nginx_conf, err = compile_nginx_conf(kong_config)
  if not nginx_conf then return nil, err end
  local ok, err = pl_file.write(nginx_config_path, nginx_conf)
  if not ok then return nil, err end

  -- write Kong's NGINX conf
  local kong_nginx_conf, err = compile_kong_conf(kong_config)
  if not kong_nginx_conf then return nil, err end
  local ok, err = pl_file.write(kong_nginx_conf_path, kong_nginx_conf)
  if not ok then return nil, err end

  return true
end

return {
  compile_nginx_conf = compile_nginx_conf,
  compile_kong_conf = compile_kong_conf,
  prepare_prefix = prepare_prefix
}
