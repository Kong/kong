local https_server = {}
https_server.__index = https_server


local fmt = string.format
local nginx_tpl_file = require 'spec.fixtures.nginx_conf_template'
local ngx = require 'ngx'
local pl_dir = require 'pl.dir'
local pl_file = require 'pl.file'
local pl_template = require 'pl.template'
local pl_path = require "pl.path"
local pl_text = require 'pl.text'
local uuid = require "resty.jit-uuid"


-- we need this to get random UUIDs
math.randomseed(os.time())


local tmp_root = os.getenv("TMPDIR") or "/tmp"


local function create_temp_dir(copy_cert_and_key)
  local tmp_name = fmt("nginx_%s", uuid())
  local tmp_path = fmt("%s/%s", tmp_root, tmp_name)
  local _, err = pl_path.mkdir(tmp_path)
  if err then
    return nil, err
  end

  local _, err = pl_path.mkdir(tmp_path .. "/logs")
  if err then
    return nil, err
  end

  if copy_cert_and_key then
    local status = pl_dir.copyfile('./spec/fixtures/kong_spec.crt', tmp_path)
    if not status then
      return nil, "could not copy cert"
    end

    status = pl_dir.copyfile('./spec/fixtures/kong_spec.key', tmp_path)
    if not status then
      return nil, "could not copy private key"
    end
  end

  return tmp_path
end


local function create_conf(params)
  local tpl, err = pl_template.compile(nginx_tpl_file)
  if err then
    return nil, err
  end

  local compiled_tpl = pl_text.Template(tpl:render(params, { ipairs = ipairs }))
  local conf_filename = params.base_path .. "/nginx.conf"
  local conf, err = io.open (conf_filename, "w")
  if err then
    return nil, err
  end

  conf:write(compiled_tpl:substitute(params))
  conf:close()

  return conf_filename
end


local function count_results(logs_dir)
  local results = {
    ['ok'] = 0,
    ['fail'] = 0,
    ['total'] = 0,
    ['status_ok'] = 0,
    ['status_fail'] = 0,
    ['status_total'] = 0
  }
  local error_log_filename = logs_dir .. "/error.log"

  for line in io.lines(error_log_filename) do
    local m = ngx.re.match(line, [[^.*\[COUNT\] (.+) (\d\d\d)\,.*\, host: \"(.+)\"$]])
    if m then
      local location = m[1]
      local status = m[2]
      local host = m[3]
      if host then
        host = string.match(m[3], "[^:]+")
      else
        host = 'nonamehost'
      end
      if results[host] == nil then
        results[host] = {
          ['ok'] = 0,
          ['fail'] = 0,
          ['status_ok'] = 0,
          ['status_fail'] = 0,
        }
      end

      if location == 'slash' then
        if status == '200' then
          results.ok = results.ok + 1
          results[host].ok = results[host].ok + 1
        else
          results.fail = results.fail + 1
          results[host].fail = results[host].fail + 1
        end
        results.total = results.ok + results.fail
      elseif location == 'status' then
        if status == '200' then
          results.status_ok = results.status_ok + 1
          results[host].status_ok = results[host].status_ok + 1
        else
          results.status_fail = results.status_fail + 1
          results[host].status_fail = results[host].status_fail + 1
        end
        results.status_total = results.status_ok + results.status_fail
      end
    end
  end

  return results
end


function https_server.start(self)
  if not pl_path.exists(tmp_root) or not pl_path.isdir(tmp_root) then
    error("could not get a temporary path", 2)
  end

  local err
  self.base_path, err = create_temp_dir(self.protocol == "https")
  if err then
    error(fmt("could not create temp dir: %s", err), 2)
  end

  local conf_params = {
    base_path = self.base_path,
    cert_path = "./",
    check_hostname = self.check_hostname,
    logs_dir = self.logs_dir,
    host = self.host,
    hosts = self.hosts,
    http_port = self.http_port,
    protocol = self.protocol,
    worker_num = self.worker_num,
  }

  local file, err = create_conf(conf_params)
  if err then
    error(fmt("could not create conf: %s", err), 2)
  end

  local status = os.execute("nginx -c " .. file .. " -p " .. self.base_path)
  if not status then
    error("failed starting nginx")
  end
end


function https_server.shutdown(self)
  local pid_filename = self.base_path .. "/logs/nginx.pid"
  local pid_file = io.open (pid_filename, "r")
  if pid_file then
    local pid, err = pid_file:read()
    if err then
      error(fmt("could not read pid file: %s", tostring(err)), 2)
    end

    local kill_nginx_cmd = fmt("kill -s TERM %s", tostring(pid))
    local status = os.execute(kill_nginx_cmd)
    if not status then
      error(fmt("could not kill nginx test server. %s was not removed", self.base_path), 2)
    end

    local pidfile_removed
    local watchdog = 0
    repeat
      pidfile_removed = pl_file.access_time(pid_filename) == nil
      if not pidfile_removed then
        ngx.sleep(0.01)
        watchdog = watchdog + 1
        if(watchdog > 100) then
          error("could not stop nginx", 2)
        end
      end
    until(pidfile_removed)
  end

  local count, err = count_results(self.base_path .. "/" .. self.logs_dir)
  if err then
    -- not a fatal error
    print(fmt("could not count results: %s", tostring(err)))
  end

  local _, err = pl_dir.rmtree(self.base_path)
  if err then
    print(fmt("could not remove %s: %s", self.base_path, tostring(err)))
  end

  return count
end


function https_server.new(port, hostname, protocol, check_hostname, workers)
  local self = setmetatable({}, https_server)
  local host
  local hosts

  if type(hostname) == 'table' then
    hosts = hostname
    host = ""
    for _, h in ipairs(hostname) do
      host = fmt("%s %s", host, h)
    end
  else
    hosts = {hostname}
    host = hostname
  end

  self.check_hostname = check_hostname or false
  self.host = host or 'localhost'
  self.hosts = hosts
  self.http_port = port
  self.logs_dir = 'logs'
  self.protocol = protocol or 'http'
  self.worker_num = workers or 2

  return self
end

return https_server
