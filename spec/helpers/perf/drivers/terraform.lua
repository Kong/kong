local perf = require("spec.helpers.perf")
local pl_path = require("pl.path")
local cjson = require("cjson")
local tools = require("kong.tools.utils")
math.randomseed(os.time())

local _M = {}
local mt = {__index = _M}

local UPSTREAM_PORT = 8088
local KONG_ADMIN_PORT
local PG_PASSWORD = tools.random_string()
local KONG_ERROR_LOG_PATH = "/tmp/error.log"
local KONG_DEFAULT_HYBRID_CERT = "/tmp/kong-hybrid-cert.pem"
local KONG_DEFAULT_HYBRID_CERT_KEY = "/tmp/kong-hybrid-key.pem"
-- threshold for load_avg / nproc, not based on specific research,
-- just a arbitrary number to ensure test env is normalized
local LOAD_NORMALIZED_THRESHOLD = 0.2

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

  local ssh_user = "root"
  if opts.provider == "aws-ec2" then
    ssh_user = "ubuntu"
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
    systemtap_sanity_checked = false,
    systemtap_dest_path = nil,
    daily_image_desc = nil,
    ssh_user = ssh_user,
  }, mt)
end

local function ssh_execute_wrap(self, ip, cmd)
  -- to quote a ', one need to finish the current ', quote the ' then start a new '
  cmd = string.gsub(cmd, "'", "'\\''")
  return "ssh " ..
          "-o IdentityFile=" .. self.work_dir .. "/id_rsa " .. -- TODO: no hardcode
          -- timeout is detected 3xServerAliveInterval
          "-o TCPKeepAlive=yes -o ServerAliveInterval=10 " ..
          -- turn on connection multiplexing
          "-o ControlPath=" .. self.work_dir .. "/cm-%r@%h:%p " ..
          "-o ControlMaster=auto -o ControlPersist=5m " ..
          -- no interactive prompt for saving hostkey
          "-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no " ..
          -- silence warnings like "Permanently added xxx"
          "-o LogLevel=ERROR " ..
          self.ssh_user .. "@" .. ip .. " '" .. cmd .. "'"
end

-- if remote_ip is set, run remotely; else run on host machine
local function execute_batch(self, remote_ip, cmds, continue_on_error)
  for _, cmd in ipairs(cmds) do
    if remote_ip then
      cmd = ssh_execute_wrap(self, remote_ip, cmd)
    end
    local _, err = perf.execute(cmd, {
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

function _M:remote_execute(node_type, cmds, continue_on_error)
  local ip
  if node_type == "kong" then
    ip = self.kong_ip
  elseif node_type == "worker" then
    ip = self.worker_ip
  elseif node_type == "db" then
    ip = self.db_ip
  else
    return false, "unknown node type: " .. node_type
  end
  return execute_batch(self, ip, cmds, continue_on_error)
end

function _M:setup(opts)
  local bin, err = perf.execute("which terraform")
  if err or #bin == 0 then
    return nil, "terraform binary not found"
  end

  local ok, _
  -- terraform apply
  self.log.info("Running terraform to provision instances...")

  _, err = execute_batch(self, nil, {
    "terraform version",
    "cd " .. self.work_dir .. " && terraform init",
    "cd " .. self.work_dir .. " && terraform apply -auto-approve " .. self.tfvars,
  })
  if err then
    return false, err
  end

  -- grab outputs
  local res
  res, err = perf.execute("cd " .. self.work_dir .. " && terraform output -json")
  if err then
    return false, "terraform show: " .. err
  end
  res = cjson.decode(res)

  self.kong_ip = res["kong-ip"].value
  self.kong_internal_ip = res["kong-internal-ip"].value
  if self.opts.seperate_db_node then
    self.db_ip = res["db-ip"].value
    self.db_internal_ip = res["db-internal-ip"].value
  else
    self.db_ip = self.kong_ip
    self.db_internal_ip = self.kong_internal_ip
  end
  self.worker_ip = res["worker-ip"].value
  self.worker_internal_ip = res["worker-internal-ip"].value

  -- install psql docker on db instance
  ok, err = execute_batch(self, self.db_ip, {
    "sudo apt-get purge unattended-upgrades -y",
    "sudo apt-get update -qq", "sudo DEBIAN_FRONTEND=\"noninteractive\" apt-get install -y --force-yes docker.io",
    "sudo docker rm -f kong-database || true", -- if exist remove it
    "sudo docker volume rm $(sudo docker volume ls -qf dangling=true) || true", -- cleanup postgres volumes if any
    "sudo docker run -d -p5432:5432 "..
            "-e POSTGRES_PASSWORD=" .. PG_PASSWORD .. " " ..
            "-e POSTGRES_DB=kong_tests " ..
            "-e POSTGRES_USER=kong --name=kong-database postgres:13 postgres -N 2333",
  })
  if not ok then
    return ok, err
  end

  -- wait
  local cmd = ssh_execute_wrap(self, self.db_ip,
                              "sudo docker logs -f kong-database")
  if not perf.wait_output(cmd, "is ready to accept connections", 5) then
    return false, "timeout waiting psql to start (5s)"
  end

  return true
end

function _M:teardown(full)
  self.setup_kong_called = false

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

  perf.git_restore()

  -- otherwise do nothing
  return true
end

function _M:start_worker(conf, port_count)
  conf = conf or ""
  local listeners = {}
  for i=1,port_count do
    listeners[i] = ("listen %d reuseport;"):format(UPSTREAM_PORT+i-1)
  end
  listeners = table.concat(listeners, "\n")

  conf = ngx.encode_base64(([[
  worker_processes auto;
  worker_cpu_affinity auto;
  error_log /var/log/nginx/error.log;
  pid /run/nginx.pid;
  worker_rlimit_nofile 20480;

  events {
     accept_mutex off;
     worker_connections 10620;
  }

  http {
     access_log off;
     server_tokens off;
     keepalive_requests 10000;
     tcp_nodelay on;

     server {
         %s
         location =/health {
            return 200;
         }
         location / {
             return 200 " performancetestperformancetestperformancetestperformancetestperformancetest";
         }
         %s
     }
  }]]):format(listeners, conf)):gsub("\n", "")

  local ok, err = execute_batch(self, self.worker_ip, {
    "sudo id",
    "echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor || true",
    "sudo apt-get purge unattended-upgrades -y",
    "sudo apt-get update -qq", "sudo DEBIAN_FRONTEND=\"noninteractive\" apt-get install -y --force-yes nginx gcc make unzip libssl-dev zlib1g-dev",
    "which wrk || (rm -rf wrk && git clone https://github.com/wg/wrk -b 4.2.0 && cd wrk && make -j$(nproc) WITH_OPENSSL=/usr && sudo cp wrk /usr/local/bin/wrk)",
    "which wrk2 || (rm -rf wrk2 && git clone https://github.com/giltene/wrk2 && cd wrk2 && make -j$(nproc) && sudo cp wrk /usr/local/bin/wrk2)",
    "echo " .. conf .. " | base64 -d | sudo tee /etc/nginx/nginx.conf",
    "sudo nginx -t",
    "sudo systemctl restart nginx",
  })
  if not ok then
    return nil, err
  end

  local uris = {}
  for i=1,port_count do
    uris[i] = "http://" .. self.worker_internal_ip .. ":" .. UPSTREAM_PORT+i-1
  end
  return uris
end

local function get_admin_port(self, kong_name)
  kong_name = kong_name or "default"
  local port, err = perf.execute(ssh_execute_wrap(self, self.kong_ip,
    "sudo cat /etc/kong/" .. kong_name .. ".conf | grep admin_listen | cut -d ':' -f 2 | grep -oP '\\d+' || true"))
  if port and tonumber(port) then
    return tonumber(port)
  else
    self.log.warn("unable to read admin port for " .. kong_name .. ", fallback to default port " .. KONG_ADMIN_PORT .. ": " .. tostring(err))
    return KONG_ADMIN_PORT
  end
end

local function prepare_spec_helpers(self, use_git, version)
  perf.setenv("KONG_PG_HOST", self.db_ip)
  perf.setenv("KONG_PG_PASSWORD", PG_PASSWORD)
  -- self.log.debug("(In a low voice) pg_password is " .. PG_PASSWORD)

  if not use_git then
    local current_spec_helpers_version = perf.get_kong_version(true)
    if current_spec_helpers_version ~= version then
      self.log.info("Current spec helpers version " .. current_spec_helpers_version ..
      " doesn't match with version to be tested " .. version .. ", checking out remote version")

      version = version:match("%d+%.%d+%.%d+")

      perf.git_checkout(version) -- throws
    end
  end

  self.log.info("Infra is up! However, preapring database remotely may take a while...")
  for i=1, 3 do
    perf.clear_loaded_package()

    -- just to let spec.helpers happy, we are not going to start kong locally
    require("kong.meta")._DEPENDENCIES.nginx = {"0.0.0.0", "9.9.9.9"}

    local pok, pret = pcall(require, "spec.helpers")
    package.loaded['kong.meta'] = nil
    require("kong.meta")

    if pok then
      pret.admin_client = function(timeout)
        return pret.http_client(self.kong_ip, get_admin_port(self), timeout or 60000)
      end
      perf.unsetenv("KONG_PG_HOST")
      perf.unsetenv("KONG_PG_PASSWORD")

      return pret
    end
    self.log.warn("unable to load spec.helpers: " .. (pret or "nil") .. ", try " .. i)
    ngx.sleep(1)
  end
  error("Unable to load spec.helpers")
end

function _M:setup_kong(version)
  local ok, err = _M.setup(self)
  if not ok then
    return ok, err
  end

  local git_repo_path, _

  if version:startswith("git:") then
    git_repo_path = perf.git_checkout(version:sub(#("git:")+1))

    version = perf.get_kong_version()
    self.log.debug("current git hash resolves to Kong version ", version)
  end

  local download_path
  local download_user, download_pass = "x", "x"
  if version:sub(1, 1) == "2" then
    download_path = "https://download.konghq.com/gateway-2.x-ubuntu-focal/pool/all/k/kong/kong_" ..
                    version .. "_amd64.deb"
  else
    error("Unknown download location for Kong version " .. version)
  end

  local docker_extract_cmds
  self.daily_image_desc = nil
  -- daily image are only used when testing with git
  -- testing upon release artifact won't apply daily image files
  local daily_image = "kong/kong:master-nightly-ubuntu"
  if self.opts.use_daily_image and git_repo_path then
    -- install docker on kong instance
    local _, err = execute_batch(self, self.kong_ip, {
      "sudo apt-get update -qq",
      "sudo DEBIAN_FRONTEND=\"noninteractive\" apt-get install -y --force-yes docker.io",
      "sudo docker version",
    })
    if err then
      return false, err
    end

    docker_extract_cmds = {
      "sudo docker rm -f daily || true",
      "sudo docker rmi -f " .. daily_image,
      "sudo docker pull " .. daily_image,
      "sudo docker create --name daily " .. daily_image,
      "sudo rm -rf /tmp/lua && sudo docker cp daily:/usr/local/share/lua/5.1/. /tmp/lua",
      -- don't overwrite kong source code, use them from current git repo instead
      "sudo rm -rf /tmp/lua/kong && sudo cp -r /tmp/lua/. /usr/local/share/lua/5.1/",
    }

    for _, dir in ipairs({"/usr/local/openresty",
                          "/usr/local/kong/include", "/usr/local/kong/lib"}) do
      -- notice the /. it makes sure the content not the directory itself is copied
      table.insert(docker_extract_cmds, "sudo docker cp daily:" .. dir .."/. " .. dir)
    end

    table.insert(docker_extract_cmds, "sudo rm -rf /tmp/lua && sudo docker cp daily:/usr/local/share/lua/5.1/. /tmp/lua")
    table.insert(docker_extract_cmds, "sudo rm -rf /tmp/lua/kong && sudo cp -r /tmp/lua/. /usr/local/share/lua/5.1/")
  end

  local ok, err = execute_batch(self, self.kong_ip, {
    "sudo apt-get purge unattended-upgrades -y",
    "sudo apt-get update -qq",
    "echo | sudo tee " .. KONG_ERROR_LOG_PATH, -- clear it
    "sudo id",
    -- set cpu scheduler to performance, it should lock cpufreq to static freq
    "echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor || true",
    -- increase outgoing port range to avoid 99: Cannot assign requested address
    "sudo sysctl net.ipv4.ip_local_port_range='10240 65535'",
    -- stop and remove kong if installed
    "dpkg -l kong && (sudo kong stop; sudo dpkg -r kong) || true",
    -- have to do the pkill sometimes, because kong stop allow the process to linger for a while
    "sudo pkill -F /usr/local/kong/pids/nginx.pid || true",
    -- remove all lua files, not only those installed by package
    "sudo rm -rf /usr/local/share/lua/5.1/kong",
    "wget -nv " .. download_path ..
        " --user " .. download_user .. " --password " .. download_pass .. " -O kong-" .. version .. ".deb",
    "sudo dpkg -i kong-" .. version .. ".deb || sudo apt-get -f -y install",
    -- generate hybrid cert
    "kong hybrid gen_cert " .. KONG_DEFAULT_HYBRID_CERT .. " " .. KONG_DEFAULT_HYBRID_CERT_KEY .. " || true",
  })
  if not ok then
    return false, err
  end

  if docker_extract_cmds then
    _, err = execute_batch(self, self.kong_ip, docker_extract_cmds)
    if err then
      return false, "error extracting docker daily image:" .. err
    end
    local manifest
    manifest, err = perf.execute(ssh_execute_wrap(self, self.kong_ip, "sudo docker inspect " .. daily_image))
    if err then
      return nil, "failed to inspect daily image: " .. err
    end
    local labels
    labels, err = perf.parse_docker_image_labels(manifest)
    if err then
      return nil, "failed to use parse daily image manifest: " .. err
    end

    self.log.debug("daily image " .. labels.version .." was pushed at ", labels.created)
    self.daily_image_desc = labels.version .. ", " .. labels.created
  end

  local kong_conf = {}
  kong_conf["pg_host"] = self.db_internal_ip
  kong_conf["pg_password"] = PG_PASSWORD
  kong_conf["pg_database"] = "kong_tests"

  local kong_conf_blob = ""
  for k, v in pairs(kong_conf) do
    kong_conf_blob = string.format("%s\n%s=%s\n", kong_conf_blob, k, v)
  end
  kong_conf_blob = ngx.encode_base64(kong_conf_blob):gsub("\n", "")

  _, err = execute_batch(self, nil, {
    -- upload
    git_repo_path and ("(cd " .. git_repo_path .. " && tar zc kong) | " .. ssh_execute_wrap(self, self.kong_ip,
      "sudo tar zx -C /usr/local/share/lua/5.1")) or "echo use stock files",
    git_repo_path and (ssh_execute_wrap(self, self.kong_ip,
      "sudo cp -r /usr/local/share/lua/5.1/kong/include/. /usr/local/kong/include/ && sudo chmod 777 -R /usr/local/kong/include/ || true"))
      or "echo use stock files",
    -- run migrations with default configurations
    ssh_execute_wrap(self, self.kong_ip,
      "sudo mkdir -p /etc/kong"),
    ssh_execute_wrap(self, self.kong_ip,
      "echo " .. kong_conf_blob .. " | base64 -d | sudo tee /etc/kong/kong.conf"),
    ssh_execute_wrap(self, self.kong_ip,
      "sudo kong migrations bootstrap"),
    ssh_execute_wrap(self, self.kong_ip,
      "sudo kong migrations up -y || true"),
    ssh_execute_wrap(self, self.kong_ip,
      "sudo kong migrations finish -y || true"),
  })
  if err then
    return false, err
  end

  self.setup_kong_called = true

  return prepare_spec_helpers(self, git_repo_path, version)
end

function _M:start_kong(kong_conf, driver_conf)
  if not self.setup_kong_called then
    return false, "setup_kong() must be called before start_kong()"
  end

  local kong_name = driver_conf and driver_conf.name or "default"
  local prefix = "/usr/local/kong_" .. kong_name
  local conf_path = "/etc/kong/" .. kong_name .. ".conf"

  kong_conf = kong_conf or {}
  kong_conf["prefix"] = kong_conf["prefix"] or prefix
  kong_conf["pg_host"] = kong_conf["pg_host"] or self.db_internal_ip
  kong_conf["pg_password"] = kong_conf["pg_password"] or PG_PASSWORD
  kong_conf["pg_database"] = kong_conf["pg_database"] or "kong_tests"

  kong_conf['proxy_access_log'] = kong_conf['proxy_access_log'] or "/dev/null"
  kong_conf['proxy_error_log'] = kong_conf['proxy_error_log'] or KONG_ERROR_LOG_PATH
  kong_conf['admin_error_log'] = kong_conf['admin_error_log'] or KONG_ERROR_LOG_PATH

  KONG_ADMIN_PORT = 39001
  kong_conf['admin_listen'] = kong_conf['admin_listen'] or ("0.0.0.0:" .. KONG_ADMIN_PORT)
  kong_conf['vitals'] = kong_conf['vitals'] or "off"
  kong_conf['anonymous_reports'] = kong_conf['anonymous_reports'] or "off"
  if not kong_conf['cluster_cert'] then
    kong_conf['cluster_cert'] = KONG_DEFAULT_HYBRID_CERT
    kong_conf['cluster_cert_key'] = KONG_DEFAULT_HYBRID_CERT_KEY
  end

  local kong_conf_blob = ""
  for k, v in pairs(kong_conf) do
    kong_conf_blob = string.format("%s\n%s=%s\n", kong_conf_blob, k, v)
  end
  kong_conf_blob = ngx.encode_base64(kong_conf_blob):gsub("\n", "")

  local _, err = execute_batch(self, self.kong_ip, {
    "mkdir -p /etc/kong || true",
    "echo " .. kong_conf_blob .. " | base64 -d | sudo tee " .. conf_path,
    "sudo rm -rf " .. prefix .. " && sudo mkdir -p " .. prefix .. " && sudo chown kong:kong -R " .. prefix,
    "sudo kong check " .. conf_path,
    string.format("sudo kong migrations up -y -c %s || true", conf_path),
    string.format("sudo kong migrations finish -y -c %s || true", conf_path),
    string.format("ulimit -n 655360; sudo kong start -c %s || sudo kong restart -c %s", conf_path, conf_path),
    -- set mapping of kong name to IP for use like Hybrid mode
    "grep -q 'START PERF HOSTS' /etc/hosts || (echo '## START PERF HOSTS' | sudo tee -a /etc/hosts)",
    "echo " .. self.kong_internal_ip .. " " .. kong_name .. " | sudo tee -a /etc/hosts",
  })
  if err then
    return false, err
  end

  return true
end

function _M:stop_kong()
  local load, err = perf.execute(ssh_execute_wrap(self, self.kong_ip,
              "cat /proc/loadavg"))
  if err then
    self.log.err("failed to get loadavg: " .. err)
  end

  self.log.debug("Kong node end 1m loadavg is ", load:match("[%d%.]+"))

  return execute_batch(self, self.kong_ip, {
    "sudo pkill -kill nginx",
    "sudo sed '/START PERF HOSTS/Q' -i /etc/hosts",
  })
end

function _M:get_start_load_cmd(stub, script, uri)
  if not uri then
    uri = string.format("http://%s:8000", self.kong_internal_ip)
  end

  local script_path
  if script then
    script_path = string.format("/tmp/wrk-%s.lua", tools.random_string())
    local out, err = perf.execute(
      ssh_execute_wrap(self, self.worker_ip, "tee " .. script_path),
      {
        stdin = script,
      })
    if err then
      return false, "failed to write script in remote machine: " .. (out or err)
    end
  end

  script_path = script_path and ("-s " .. script_path) or ""

  local nproc, err
  nproc, err = perf.execute(ssh_execute_wrap(self, self.kong_ip, "nproc"))
  if not nproc or err then
    return false, "failed to get nproc: " .. (err or "")
  end

  if not tonumber(nproc) then
    return false, "failed to get nproc: " .. (nproc or "")
  end
  nproc = tonumber(nproc)

  local loadavg

  while true do
    loadavg, err = perf.execute(ssh_execute_wrap(self, self.kong_ip,
              "cat /proc/loadavg"))
    if not loadavg or err then
      self.log.err("failed to get loadavg: ", (err or ""))
      goto continue
    end

    loadavg = loadavg:match("[%d%.]+")
    if not loadavg or not tonumber(loadavg) then
      self.log.err("failed to get loadavg: ", loadavg or "nil")
      goto continue
    end
    loadavg = tonumber(loadavg)

    local load_normalized = loadavg / nproc
    if load_normalized < LOAD_NORMALIZED_THRESHOLD then
      break
    end

    self.log.info("waiting for Kong node 1m loadavg to drop under ",
                  nproc * LOAD_NORMALIZED_THRESHOLD, ", now: ", loadavg)
    ngx.sleep(15)

    ::continue::
  end
  self.log.debug("Kong node start 1m loadavg is ", loadavg)

  return ssh_execute_wrap(self, self.worker_ip,
            stub:format(script_path, uri))
end

function _M:get_admin_uri(kong_name)
  return string.format("http://%s:%s", self.kong_internal_ip, get_admin_port(self, kong_name))
end

local function check_systemtap_sanity(self)
  local _, err
  _, err = perf.execute(ssh_execute_wrap(self, self.kong_ip, "which stap"))
  if err then
    _, err = execute_batch(self, self.kong_ip, {
      "sudo DEBIAN_FRONTEND=\"noninteractive\" apt-get install g++ libelf-dev libdw-dev libssl-dev libsqlite3-dev libnss3-dev pkg-config python3 make -y --force-yes",
      "wget https://sourceware.org/systemtap/ftp/releases/systemtap-4.6.tar.gz -O systemtap.tar.gz",
      "tar xf systemtap.tar.gz",
      "cd systemtap-*/ && " .. 
        "./configure --enable-sqlite --enable-bpf --enable-nls --enable-nss --enable-avahi && " ..
        "make PREFIX=/usr -j$(nproc) && "..
        "sudo make install"
    })
    if err then
      return false, "failed to build systemtap: " .. err
    end
  end

  _, err = execute_batch(self, self.kong_ip, {
    "sudo DEBIAN_FRONTEND=\"noninteractive\" apt-get install gcc linux-headers-$(uname -r) -y --force-yes",
    "which stap",
    "stat /tmp/stapxx || git clone https://github.com/Kong/stapxx /tmp/stapxx",
    "stat /tmp/perf-ost || git clone https://github.com/openresty/openresty-systemtap-toolkit /tmp/perf-ost",
    "stat /tmp/perf-fg || git clone https://github.com/brendangregg/FlameGraph /tmp/perf-fg"
  })
  if err then
    return false, err
  end

  -- try compile the kernel module
  local out
  out, err = perf.execute(ssh_execute_wrap(self, self.kong_ip,
          "sudo stap -ve 'probe begin { print(\"hello\\n\"); exit();}'"))
  if err then
    return nil, "systemtap failed to compile kernel module: " .. (out or "nil") ..
                " err: " .. (err or "nil") .. "\n Did you install gcc and kernel headers?"
  end

  return true
end

function _M:get_start_stapxx_cmd(sample, args, driver_conf)
  if not self.systemtap_sanity_checked then
    local ok, err = check_systemtap_sanity(self)
    if not ok then
      return nil, err
    end
    self.systemtap_sanity_checked = true
  end

  -- find one of kong's child process hopefully it's a worker
  -- (does kong have cache loader/manager?)
  local kong_name = driver_conf and driver_conf.name or "default"
  local prefix = "/usr/local/kong_" .. kong_name
  local pid, err = perf.execute(ssh_execute_wrap(self, self.kong_ip,
                      "pid=$(cat " .. prefix .. "/pids/nginx.pid); " ..
                      "cat /proc/$pid/task/$pid/children | awk '{print $1}'"))
  if err or not tonumber(pid) then
    return nil, "failed to get Kong worker PID: " .. (err or "nil")
  end

  self.systemtap_dest_path = "/tmp/" .. tools.random_string()
  return ssh_execute_wrap(self, self.kong_ip,
            "sudo /tmp/stapxx/stap++ /tmp/stapxx/samples/" .. sample ..
            " --skip-badvars -D MAXSKIPPED=1000000 -x " .. pid ..
            " " .. args ..
            " > " .. self.systemtap_dest_path .. ".bt"
          )
end

function _M:get_wait_stapxx_cmd(timeout)
  return ssh_execute_wrap(self, self.kong_ip, "lsmod | grep stap_")
end

function _M:generate_flamegraph(title, opts)
  local path = self.systemtap_dest_path
  self.systemtap_dest_path = nil

  local out, err = perf.execute(ssh_execute_wrap(self, self.kong_ip, "cat " .. path .. ".bt"))
  if err or #out == 0 then
    return nil, "systemtap output is empty, possibly no sample are captured"
  end

  local ok, err = execute_batch(self, self.kong_ip, {
    "/tmp/perf-ost/fix-lua-bt " .. path .. ".bt > " .. path .. ".fbt",
    "/tmp/perf-fg/stackcollapse-stap.pl " .. path .. ".fbt > " .. path .. ".cbt",
    "/tmp/perf-fg/flamegraph.pl --title='" .. title .. "' " .. (opts or "") .. " " .. path .. ".cbt > " .. path .. ".svg",
  })
  if not ok then
    return false, err
  end

  local out, _ = perf.execute(ssh_execute_wrap(self, self.kong_ip, "cat " .. path .. ".svg"))

  perf.execute(ssh_execute_wrap(self, self.kong_ip, "sudo rm -v " .. path .. ".*"),
              { logger = self.ssh_log.log_exec })

  return out
end

function _M:save_error_log(path)
  return perf.execute(ssh_execute_wrap(self, self.kong_ip,
          "cat " .. KONG_ERROR_LOG_PATH) .. " >'" .. path .. "'",
          { logger = self.ssh_log.log_exec })
end

function _M:save_pgdump(path)
  return perf.execute(ssh_execute_wrap(self, self.kong_ip,
      "sudo docker exec -i kong-database psql -Ukong kong_tests --data-only") .. " >'" .. path .. "'",
      { logger = self.ssh_log.log_exec })
end

function _M:load_pgdump(path, dont_patch_service)
  local _, err = perf.execute("cat " .. path .. "| " .. ssh_execute_wrap(self, self.kong_ip,
      "sudo docker exec -i kong-database psql -Ukong kong_tests"),
      { logger = self.ssh_log.log_exec })
  if err then
    return false, err
  end

  if dont_patch_service then
    return true
  end

  return perf.execute("echo \"UPDATE services set host='" .. self.worker_ip ..
                                                "', port=" .. UPSTREAM_PORT ..
                                                ", protocol='http';\" | " ..
      ssh_execute_wrap(self, self.kong_ip,
      "sudo docker exec -i kong-database psql -Ukong kong_tests"),
      { logger = self.ssh_log.log_exec })
end

function _M:get_based_version()
  return self.daily_image_desc or perf.get_kong_version()
end

return _M
