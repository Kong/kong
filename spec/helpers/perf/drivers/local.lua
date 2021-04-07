local perf = require("spec.helpers.perf")
local pl_path = require("pl.path")
local helpers

local _M = {}
local mt = {__index = _M}

local UPSTREAM_PORT = 62412

function _M.new(opts)
  return setmetatable({
    opts = opts,
    log = perf.new_logger("[local]"),
    upstream_nginx_pid = nil,
    nginx_bin = nil,
    wrk_bin = nil,
    load_thread = nil,
    load_should_stop = true,
    git_head = nil,
    git_stashed = false,
  }, mt)
end

function _M:setup()
  local bin, err
  for _, test in ipairs({"nginx", "/usr/local/openresty/nginx/sbin/nginx"}) do
    bin, err = perf.execute("which nginx")
    if bin then
      self.nginx_bin = bin
      break
    end
  end

  if not self.nginx_bin then
    return nil, "nginx binary not found, either install nginx package or Kong"
  end

  bin, err = perf.execute("which wrk")
  if not bin then
    return nil, "wrk binary not found"
  end
  self.wrk_bin = bin

  bin, err = perf.execute("which git")
  if not bin then
    return nil, "git binary not found"
  end

  package.loaded["spec.helpers"] = nil
  helpers = require("spec.helpers")
  return helpers
end

function _M:teardown()
  if self.upstream_nginx_pid then
    local ok, err = perf.execute("kill " .. self.upstream_nginx_pid)
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
      access_log access.log;
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
  local hash, err = perf.execute("git rev-parse HEAD")
  if not hash or not hash:match("[a-f0-f]+") then
    self.log.warn("\"version\" is ignored when not in a git repository")
  else
    -- am i on a named branch/tag?
    local n, err = perf.execute("git rev-parse --abbrev-ref HEAD")
    if n then
      hash = n
    end
    -- anything to save?
    n, err = perf.execute("git status --untracked-files=no --porcelain")
    if not err and (n and #n > 0) then
      self.log.info("saving your working directory")
      n, err = perf.execute("git stash save kong-perf-test-autosaved")
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

-- @param opts.path string request path
-- @param opts.connections number connection count
-- @param opts.threads number request thread count
-- @param opts.duration number perf test duration
function _M:start_load(opts)
  if self.load_thread then
    return false, "load is already started, stop it using stop_load() first"
  end

  local kong_ip = helpers.get_proxy_ip()
  local kong_port = helpers.get_proxy_port()

  self.load_should_stop = false

  opts = opts or {}

  self.load_thread = ngx.thread.spawn(function()
    return perf.execute(
        " wrk -c " .. (opts.connections or 1000) ..
        " -t " .. (opts.threads or 5) ..
        " -d " .. (opts.duration or 10) ..
        (" http://%s:%d/%s"):format(kong_ip, kong_port, opts.path or ""),
        {
          stop_signal = function() if self.load_should_stop then return 9 end end,
        })
  end)

  return true
end

function _M:wait_result(opts)
  local ok, res, err = ngx.thread.wait(self.load_thread)
  self.load_should_stop = true
  self.load_thread = nil

  if not ok then
    return false, "failed to wait result: " .. res
  end

  return res, err
end

return _M