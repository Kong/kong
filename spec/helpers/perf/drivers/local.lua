local perf = require("spec.helpers.perf")
local pl_path = require("pl.path")
local tools = require("kong.tools.utils")
local helpers

local _M = {}
local mt = {__index = _M}

local UPSTREAM_PORT = 62412

local WRK_SCRIPT_PREFIX = "/tmp/perf-wrk-"

function _M.new(opts)
  return setmetatable({
    opts = opts,
    log = perf.new_logger("[local]"),
    upstream_nginx_pid = nil,
    nginx_bin = nil,
    wrk_bin = nil,
    git_head = nil,
    git_stashed = false,
    systemtap_sanity_checked = false,
    systemtap_dest_path = nil,
  }, mt)
end

function _M:setup()
  local bin
  for _, test in ipairs({"nginx", "/usr/local/openresty/nginx/sbin/nginx"}) do
    bin, _ = perf.execute("which nginx")
    if bin then
      self.nginx_bin = bin
      break
    end
  end

  if not self.nginx_bin then
    return nil, "nginx binary not found, either install nginx package or Kong"
  end

  bin = perf.execute("which wrk")
  if not bin then
    return nil, "wrk binary not found"
  end
  self.wrk_bin = bin

  bin = perf.execute("which git")
  if not bin then
    return nil, "git binary not found"
  end

  package.loaded["spec.helpers"] = nil
  helpers = require("spec.helpers")
  return helpers
end

function _M:teardown()
  if self.upstream_nginx_pid then
    local _, err = perf.execute("kill " .. self.upstream_nginx_pid)
    if err then
      return false, "stopping upstream: " .. err
    end
    self.upstream_nginx_pid = nil
  end

  if self.git_head then
    local res, err = perf.execute("git checkout " .. self.git_head)
    if err then
      return false, "git checkout: " .. res
    end
    self.git_head = nil

    if self.git_stashed then
      local res, err = perf.execute("git stash pop")
      if err then
        return false, "git stash pop: " .. res
      end
      self.git_stashed = false
    end
  end

  perf.execute("rm " .. WRK_SCRIPT_PREFIX .. "*.lua")

  return self:stop_kong()
end

function _M:start_upstream(conf)
  local nginx_conf_path = "/tmp/perf-test-nginx.conf"
  local nginx_prefix = "/tmp/perf-test-nginx"
  pl_path.mkdir(nginx_prefix)

  local f = io.open(nginx_conf_path, "w")
  f:write(([[
    events {}
    pid nginx.pid;
    error_log error.log;
    http {
      access_log off;
      server {
        listen %d;
        %s
      }
    }
  ]]):format(UPSTREAM_PORT, conf))
  f:close()

  local res, err = perf.execute("nginx -c " .. nginx_conf_path ..
                                " -p " .. nginx_prefix)

  if err then
    return false, "failed to start nginx: " .. err .. ": " .. (res or "nil")
  end

  f = io.open(nginx_prefix .. "/nginx.pid")
  local pid = f:read()
  f:close()
  if not tonumber(pid) then
    return false, "pid is not a number: " .. pid
  end

  self.upstream_nginx_pid = pid

  self.log.info("upstream started at PID: " .. pid)

  return "http://localhost:" .. UPSTREAM_PORT
end

function _M:start_kong(version, kong_conf)
  local res, err
  local hash, _ = perf.execute("git rev-parse HEAD")
  if not hash or not hash:match("[a-f0-f]+") then
    self.log.warn("\"version\" is ignored when not in a git repository")
  else
    -- am i on a named branch/tag?
    local n, _ = perf.execute("git rev-parse --abbrev-ref HEAD")
    if n then
      hash = n
    end
    -- anything to save?
    n, err = perf.execute("git status --untracked-files=no --porcelain")
    if not err and (n and #n > 0) then
      self.log.info("saving your working directory")
      res, err = perf.execute("git stash save kong-perf-test-autosaved")
      if err then
        error("Cannot save your working directory: " .. err .. (res or "nil"))
      end
      self.git_stashed = true
    end

    self.log.debug("switching away from ", hash, " to ", version)

    local res, err = perf.execute("git checkout " .. version)
    if err then
      error("Cannot switch to " .. version .. ":\n" .. res)
    end
    if not self.git_head then
      self.git_head = hash
    end
  end

  return helpers.start_kong(kong_conf)
end

function _M:stop_kong()
  helpers.stop_kong()
  return true
end

function _M:get_start_load_cmd(stub, script)
  local kong_ip = helpers.get_proxy_ip()
  local kong_port = helpers.get_proxy_port()

  local script_path
  if script then
    script_path = WRK_SCRIPT_PREFIX .. tools.random_string() .. ".lua"
    local f = assert(io.open(script_path, "w"))
    assert(f:write(script))
    assert(f:close())
  end

  script_path = script_path and ("-s " .. script_path) or ""

  return stub:format(script_path, "http", kong_ip, kong_port)
end

local function check_systemtap_sanity(self)
  local bin, _ = perf.execute("which stap")
  if not bin then
    return nil, "systemtap binary not found"
  end

  -- try compile the kernel module
  local out, err = perf.execute("sudo stap -ve 'probe begin { print(\"hello\\n\"); exit();}'")
  if err then
    return nil, "systemtap failed to compile kernel module: " .. (out or "nil") ..
                " err: " .. (err or "nil") .. "\n Did you install gcc and kernel headers?"
  end

  local cmds = {
    "stat /tmp/stapxx || git clone https://github.com/Kong/stapxx /tmp/stapxx",
    "stat /tmp/perf-ost || git clone https://github.com/openresty/openresty-systemtap-toolkit /tmp/perf-ost",
    "stat /tmp/perf-fg || git clone https://github.com/brendangregg/FlameGraph /tmp/perf-fg"
  }
  for _, cmd in ipairs(cmds) do
    local _, err = perf.execute(cmd)
    if err then
      return nil, cmd .. " failed: " .. err
    end
  end

  return true
end

function _M:get_start_stapxx_cmd(sample, ...)
  if not self.systemtap_sanity_checked then
    local ok, err = check_systemtap_sanity(self)
    if not ok then
      return nil, err
    end
    self.systemtap_sanity_checked = true
  end

  -- find one of kong's child process hopefully it's a worker
  -- (does kong have cache loader/manager?)
  local pid, err = perf.execute("pid=$(cat servroot/pids/nginx.pid);" ..
                                "cat /proc/$pid/task/$pid/children | awk '{print $1}'")
  if not pid then
    return nil, "failed to get Kong worker PID: " .. (err or "nil")
  end

  local args = table.concat({...}, " ")

  self.systemtap_dest_path = "/tmp/" .. tools.random_string()
  return "sudo /tmp/stapxx/stap++ /tmp/stapxx/samples/" .. sample ..
          " --skip-badvars -D MAXSKIPPED=1000000 -x " .. pid ..
          " " .. args ..
          " > " .. self.systemtap_dest_path .. ".bt"
end

function _M:get_wait_stapxx_cmd(timeout)
  return "lsmod | grep stap_"
end

function _M:generate_flamegraph(filename)
  local path = self.systemtap_dest_path
  self.systemtap_dest_path = nil

  local f = io.open(path .. ".bt")
  if not f or f:seek("end") == 0 then
    return nil, "systemtap output is empty, possibly no sample are captured"
  end
  f:close()

  local cmds = {
    "/tmp/perf-ost/fix-lua-bt " .. path .. ".bt > " .. path .. ".fbt",
    "/tmp/perf-fg/stackcollapse.pl " .. path .. ".fbt > " .. path .. ".cbt",
    "/tmp/perf-fg/flamegraph.pl " .. path .. ".cbt > " .. path .. ".svg",
    "cat " .. path .. ".svg",
  }
  local out, err
  for _, cmd in ipairs(cmds) do
    out, err = perf.execute(cmd)
    if err then
      return nil, cmd .. " failed: " .. err
    end
  end

  perf.execute("rm " .. path .. ".*")

  return out
end

return _M