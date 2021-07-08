local perf = require("spec.helpers.perf")
local tools = require("kong.tools.utils")
local helpers

local _M = {}
local mt = {__index = _M}

local UPSTREAM_PORT = 18088

function _M.new(opts)
  return setmetatable({
    opts = opts,
    log = perf.new_logger("[docker]"),
    psql_ct_id = nil,
    kong_ct_id = nil,
    worker_ct_id = nil,
  }, mt)
end

local function start_container(cid)
  if not cid then
    return false, "container does not exist"
  end
  
  local _, err = perf.execute("docker start " .. cid)
  if err then
    return false, "docker start:" .. err
  end

  local out, err = perf.execute("docker inspect --format='{{.State.Running}}' " .. cid)
  if err then
    return false, "docker inspect:" .. err
  end

  if out:gsub("\n", "") ~= "true" then
    local out, err = perf.execute("docker logs -n5 " .. cid)
    if err then
      return false, "docker logs:" .. err
    end
    return false, out
  end

  return true
end

local function create_container(self, args, img)
  local out, err = perf.execute("docker images --format '{{.Repository}}:{{.Tag}}' " .. img)
  -- plain pattern find
  if err or not out:find(img, nil, true) then
    local _, err = perf.execute("docker pull " .. img, { logger = self.log.log_exec })
    if err then
      return false, err
    end
  end

  args = args or ""
  out, err = perf.execute("docker create " .. args .. " " .. img)
  if err then
    return false, err
  end
  local cid = out:match("^[a-f0-9]+$")
  if not cid then
    return false, "invalid container ID " .. cid
  end
  return cid
end

local function get_container_port(cid, ct_port)
  local out, err = perf.execute(
    "docker inspect " .. 
    "--format='{{range $p, $conf := .NetworkSettings.Ports}}" ..
                "{{if eq $p \"" .. ct_port .. "\" }}{{(index $conf 0).HostPort}}{{end}}" ..
              "{{end}}' " .. cid)
  if err then
    return false, "docker inspect:" .. err .. ": " .. (out or "nil")
  end

  return tonumber(out)
end

local function get_container_vip(cid)
  local out, err = perf.execute("docker inspect --format='{{.NetworkSettings.Networks.bridge.IPAddress}}' " .. cid)
  if err then
    return false, "docker inspect:" .. err .. ": " .. (out or "nil")
  end

  return out
end

function _M:teardown()
  for _, cid in ipairs({"worker_ct_id", "kong_ct_id", "psql_ct_id" }) do
    if self[cid] then
      perf.execute("docker rm -f " .. self[cid], { logger = self.log.log_exec })
      self[cid] = nil
    end
  end

  perf.git_restore()

  return true
end

local function inject_kong_admin_client(self, helpers)
  helpers.admin_client = function(timeout)
    if not self.kong_ct_id then
      error("helpers.admin_client can only be called after perf.start_kong")
    end
    local admin_port, err = get_container_port(self.kong_ct_id, "8001/tcp")
    if not admin_port then
      error("failed to get kong admin port: " .. (err or "nil"))
    end
    return helpers.http_client("127.0.0.1", admin_port, timeout or 60000)
  end
  return helpers
end

function _M:setup()
  if not self.psql_ct_id then
    local cid, err = create_container(self, "-p5432 " ..
                    "-e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_DB=kong_tests " ..
                    "-e POSTGRES_USER=kong ",
                    "postgres:11")
    if err then
      return false, "error running docker create when creating kong container: " .. err
    end
    self.psql_ct_id = cid
  end

  self.log.info("psql container ID is ", self.psql_ct_id)
  local ok, err = start_container(self.psql_ct_id)
  if not ok then
    return false, "psql is not running: " .. err
  end

  local psql_port, err = get_container_port(self.psql_ct_id, "5432/tcp")
  if not psql_port then
    return false, "failed to get psql port: " .. (err or "nil")
  end

  -- wait
  if not perf.wait_output("docker logs -f " .. self.psql_ct_id, "is ready to accept connections") then
    return false, "timeout waiting psql to start (5s)"
  end

  self.log.info("psql is started to listen at port ", psql_port)
  perf.setenv("KONG_PG_PORT", ""..psql_port)
  
  ngx.sleep(3) -- TODO: less flaky

  -- reload the spec.helpers module, since it may have been loaded with
  -- a different set of env vars
  package.loaded["spec.helpers"] = nil
  helpers = require("spec.helpers")

  return inject_kong_admin_client(self, helpers)
end

function _M:start_upstream(conf, port_count)
  if not conf then
    error("upstream conf is not defined", 2)
  end

  local listeners = {}
  for i=1,port_count do
    listeners[i] = ("listen %d reuseport;"):format(UPSTREAM_PORT+i-1)
  end
  listeners = table.concat(listeners, "\n")

  if not self.worker_ct_id then
    local _, err = perf.execute(
      "docker build --progress plain -t perf-test-upstream -",
      {
        logger = self.log.log_exec,
        stdin = ([[
        FROM nginx:alpine
        RUN apk update && apk add wrk
        RUN echo -e '\
        server {\
          %s\
          access_log off;\
          location =/health { \
            return 200; \
          } \
          %s \
        }' > /etc/nginx/conf.d/perf-test.conf

        # copy paste
        ENTRYPOINT ["/docker-entrypoint.sh"]

        STOPSIGNAL SIGQUIT

        CMD ["nginx", "-g", "daemon off;"]
      ]]):format(listeners:gsub("\n", "\\n"), conf:gsub("\n", "\\n"))
      }
    )
    if err then
      return false, err
    end

    local cid, err = create_container(self, "-p " .. UPSTREAM_PORT, "perf-test-upstream")
    if err then
      return false, "error running docker create when creating upstream: " .. err
    end
    self.worker_ct_id = cid
  end

  self.log.info("worker container ID is ", self.worker_ct_id)

  local ok, err = start_container(self.worker_ct_id)
  if not ok then
    return false, "worker is not running: " .. err
  end

  local worker_vip, err = get_container_vip(self.worker_ct_id)
  if err then
    return false, "unable to read worker container's private IP: " .. err
  end

  self.log.info("worker is started")

  if port_count == 1 then
    return "http://" .. worker_vip .. ":" .. UPSTREAM_PORT
  end

  local uris = {}
  for i=1,port_count do
    uris[i] = "http://" .. worker_vip .. ":" .. UPSTREAM_PORT+i-1
  end
  return uris
end

function _M:start_kong(version, kong_conf)
  if not version then
    error("Kong version is not defined", 2)
  end

  local use_git
  local image = "kong"

  if version:startswith("git:") then
    perf.git_checkout(version:sub(#("git:")+1))
    use_git = true

    version = perf.get_kong_version()
    self.log.debug("current git hash resolves to docker version ", version)
  elseif version:match("rc") or version:match("beta") then
    image = "kong/kong"
  end

  if not self.kong_ct_id then
    local extra_config = ""
    for k, v in pairs(kong_conf) do
      extra_config = string.format("%s -e KONG_%s=%s", extra_config, k:upper(), v)
    end
    local cid, err = create_container(self,
      "-p 8000 -p 8001 " ..
      "--link " .. self.psql_ct_id .. ":postgres " ..
      extra_config .. " " ..
      "-e KONG_PG_HOST=postgres " ..
      "-e KONG_PROXY_ACCESS_LOG=/dev/null " ..
      "-e KONG_PG_DATABASE=kong_tests " ..
      "-e KONG_ADMIN_LISTEN=0.0.0.0:8001 ",
      image .. ":" .. version)
    if err then
      return false, "error running docker create when creating kong container: " .. err
    end
    self.kong_ct_id = cid

    if use_git then
      perf.execute("docker cp ./kong " .. self.kong_ct_id .. ":/usr/local/share/lua/5.1/")
    end
  end

  self.log.info("kong container ID is ", self.kong_ct_id)
  local ok, err = start_container(self.kong_ct_id)
  if not ok then
    return false, "kong is not running: " .. err
  end

  local proxy_port, err = get_container_port(self.kong_ct_id, "8000/tcp")
  if not proxy_port then
    return false, "failed to get kong port: " .. (err or "nil")
  end

  -- wait
  if not perf.wait_output("docker logs -f " .. self.kong_ct_id, " start worker process") then
    return false, "timeout waiting kong to start (5s)"
  end
  
  self.log.info("kong is started to listen at port ", proxy_port)
  return true
end

function _M:stop_kong()
  if self.kong_ct_id then
    return perf.execute("docker stop " .. self.kong_ct_id)
  end
end

function _M:get_start_load_cmd(stub, script, uri)
  if not uri then
    if not self.kong_ct_id then
      return false, "kong container is not created yet"
    end

    local kong_vip, err = get_container_vip(self.kong_ct_id)
    if err then
      return false, "unable to read kong container's private IP: " .. err
    end
    uri = string.format("http://%s:8000", kong_vip)
  end

  local script_path
  if script then
    script_path = string.format("/tmp/wrk-%s.lua", tools.random_string())
    local out, err = perf.execute(string.format(
    "docker exec -i %s tee %s", self.worker_ct_id, script_path),
    {
      stdin = script,
    })
    if err then
      return false, "failed to write script in container: " .. (out or err)
    end
  end

  script_path = script_path and ("-s " .. script_path) or ""

  return "docker exec " .. self.worker_ct_id .. " " ..
          stub:format(script_path, uri)
end

function _M:get_start_stapxx_cmd()
  error("SystemTap support not yet implemented in docker driver")
end

function _M:get_wait_stapxx_cmd()
  error("SystemTap support not yet implemented in docker driver")
end

function _M:generate_flamegraph()
  error("SystemTap support not yet implemented in docker driver")
end

function _M:save_error_log(path)
  return perf.execute("docker logs " .. self.kong_ct_id .. " 2>'" .. path .. "'",
                      { logger = self.log.log_exec })
end

return _M
