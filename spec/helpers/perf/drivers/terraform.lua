local perf = require("spec.helpers.perf")
local pl_path = require("pl.path")
local cjson = require("cjson")
local tools = require("kong.tools.utils")
local helpers

local _M = {}
local mt = {__index = _M}

local UPSTREAM_PORT = 8088
local PG_PASSWORD = tools.random_string()

function _M.new(opts)
  local provider = opts and opts.provider or "equinix-metal"
  local work_dir = "./spec/fixtures/perf/terraform/" .. provider
  if not pl_path.exists(work_dir) then
    error("Hosting provider " .. provider .. " unsupported: expect " .. work_dir .. " to exists", 2)
  end

  local tfvars = ""
  if opts and opts.tfvars then
    for k, v in pairs(opts.tfvars) do
      tfvars = string.format("%s -var '%s=%s' ", tfvars, k, v)
    end
  end

  return setmetatable({
    opts = opts,
    log = perf.new_logger("[terraform]"),
    ssh_log = perf.new_logger("[terraform][ssh]"),
    provider = provider,
    work_dir = work_dir,
    tfvars = tfvars,
    kong_ip = nil,
    kong_internal_ip = nil,
    worker_ip = nil,
    worker_internal_ip = nil,
  }, mt)
end

local function ssh_execute_wrap(self, ip, cmd)
  return "ssh " ..
          "-o IdentityFile=" .. self.work_dir .. "/id_rsa " .. -- TODO: no hardcode
          "-o TCPKeepAlive=yes -o ServerAliveInterval=300 " ..
          -- turn on connection multiplexing
          "-o ControlPath=" .. self.work_dir .. "/cm-%r@%h:%p " ..
          "-o ControlMaster=auto -o ControlPersist=10m " ..
          -- no interactive prompt for saving hostkey
          "-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no " ..
          "root@" .. ip .. " '" .. cmd .. "'"
end

-- if remote_ip is set, run remotely; else run on host machine
local function execute_batch(self, remote_ip, cmds, continue_on_error)
  for _, cmd in ipairs(cmds) do
    if remote_ip then
      cmd = ssh_execute_wrap(self, remote_ip, cmd)
    end
    local ok, err = perf.execute(cmd, {
      logger = (remote_ip and self.ssh_log or self.log).log_exec
    })
    if err then
      if not continue_on_error then
        return false, "failed in \"" .. cmd .. "\": ".. (err or "nil")
      end
      self.log.warn("execute ", cmd, " has error: ", (err or "nil"))
    end
  end
  return true
end

function _M:setup(opts)
  local bin, err = perf.execute("which terraform")
  if not bin then
    return nil, "terraform binary not found"
  end

  local ok, err
  -- terraform apply
  self.log.info("Running terraform to provision instances...")

  ok, err = execute_batch(self, nil, {
    "terraform version",
    "cd " .. self.work_dir .. " && terraform init",
    "cd " .. self.work_dir .. " && terraform apply -auto-approve " .. self.tfvars,
  })
  if not ok then
    return false, err
  end

  -- grab outputs
  local res, err = perf.execute("cd " .. self.work_dir .. " && terraform show -json")
  if err then
    return false, "terraform show: " .. err
  end
  res = cjson.decode(res)

  self.kong_ip = res.values.outputs["kong-ip"].value
  self.kong_internal_ip = res.values.outputs["kong-internal-ip"].value
  self.worker_ip = res.values.outputs["worker-ip"].value
  self.worker_internal_ip = res.values.outputs["worker-internal-ip"].value

  -- install psql docker on kong
  ok, err = execute_batch(self, self.kong_ip, {
    "apt-get update", "apt-get install -y --force-yes docker.io",
    "docker rm -f kong-database || true", -- if exist remove it
    "docker run -d -p5432:5432 "..
            "-e POSTGRES_PASSWORD=" .. PG_PASSWORD .. " " ..
            "-e POSTGRES_DB=kong_tests " ..
            "-e POSTGRES_USER=kong --name=kong-database postgres:11",
  })
  if not ok then
    return ok, err
  end

  -- wait
  local cmd = ssh_execute_wrap(self, self.kong_ip,
                              "docker logs -f kong-database")
  if not perf.wait_output(cmd, "is ready to accept connections", 5) then
    return false, "timeout waiting psql to start (5s)"
  end
  -- slightly wait a bit: why?
  ngx.sleep(1)

  perf.setenv("KONG_PG_HOST", self.kong_ip)
  perf.setenv("KONG_PG_PASSWORD", PG_PASSWORD)
  self.log.debug("(In a low voice) pg_password is " .. PG_PASSWORD)

  self.log.info("Infra is up! However, executing psql remotely may take a while...")
  package.loaded["spec.helpers"] = nil
  helpers = require("spec.helpers")
  return helpers
end

function _M:teardown(full)
  if full then
    -- terraform destroy
    self.log.info("Running terraform to destroy instances...")

    local ok, err = execute_batch(self, nil, {
      "terraform version",
      "cd " .. self.work_dir .. " && terraform init",
      "cd " .. self.work_dir .. " && terraform destroy -auto-approve " .. self.tfvars,
    })
    if not ok then
      return false, err
    end
  end
  -- otherwise do nothing
  return true
end

function _M:start_upstream(conf)
  conf = conf or ""
  conf = ngx.encode_base64(([[server {
              listen %d;
              location =/health {
                return 200;
              }
              %s
            }]]):format(UPSTREAM_PORT, conf)):gsub("\n", "")

  local ok, err = execute_batch(self, self.worker_ip, {
    "apt-get update", "apt-get install -y --force-yes nginx",
    -- ubuntu where's wrk in apt?
    "wget -nv http://mirrors.kernel.org/ubuntu/pool/universe/w/wrk/wrk_4.1.0-3_amd64.deb -O wrk.deb",
    "dpkg -i wrk.deb || apt-get -f -y install",
    "echo " .. conf .. " | base64 -d > /etc/nginx/conf.d/perf-test.conf",
    "nginx -t",
    "systemctl restart nginx",
  })
  if not ok then
    return nil, err
  end

  return "http://" .. self.worker_internal_ip .. ":" .. UPSTREAM_PORT
end

function _M:start_kong(version, kong_conf)
  kong_conf = kong_conf or {}
  kong_conf["pg_password"] = PG_PASSWORD
  kong_conf["pg_database"] = "kong_tests"

  local kong_conf_blob = ""
  for k, v in pairs(kong_conf) do
    kong_conf_blob = string.format("%s\n%s=%s\n", kong_conf_blob, k, v)
  end
  kong_conf_blob = ngx.encode_base64(kong_conf_blob):gsub("\n", "")

  local ok, err = execute_batch(self, self.kong_ip, {
    "dpkg -l kong && (kong stop; dpkg -r kong) || true", -- stop and remove kong if installed
    "wget -nv https://bintray.com/kong/kong-deb/download_file?file_path=kong-" ..
              version .. ".focal.amd64.deb -O k.deb",
    "dpkg -i k.deb || apt-get -f -y install",
    "echo " .. kong_conf_blob .. " | base64 -d > /etc/kong/kong.conf",
    "kong check",
    "kong start || kong restart",
  })
  if not ok then
    return false, err
  end

  return true
end

function _M:stop_kong()
  return perf.execute(ssh_execute_wrap(self, self.kong_ip, "kong stop"),
                                { logger = self.ssh_log.log_exec })
end

function _M:get_start_load_cmd(stub)
  return ssh_execute_wrap(self, self.worker_ip,
            stub:format("http", self.kong_internal_ip, "8000"))
end

return _M