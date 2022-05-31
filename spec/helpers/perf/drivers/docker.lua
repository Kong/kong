local nkeys = require "table.nkeys"
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
    kong_ct_ids = {},
    worker_ct_id = nil,
    daily_image_desc = nil,
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

local function create_container(self, args, img, cmd)
  local out, err = perf.execute("docker images --format '{{.Repository}}:{{.Tag}}' " .. img)
  -- plain pattern find
  if err or not out:find(img, nil, true) then
    local _, err = perf.execute("docker pull " .. img, { logger = self.log.log_exec })
    if err then
      return false, err
    end
  end

  args = args or ""
  cmd = cmd or ""
  out, err = perf.execute("docker create " .. args .. " " .. img  .. " " .. cmd)
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
  local ct_ids = {"worker_ct_id", "psql_ct_id" }
  for _, cid in ipairs(ct_ids) do
    if self[cid] then
      perf.execute("docker rm -f " .. self[cid], { logger = self.log.log_exec })
      self[cid] = nil
    end
  end

  for conf_id, kong_ct_id in pairs(self.kong_ct_ids) do
    perf.execute("docker rm -f " .. kong_ct_id, { logger = self.log.log_exec })
    self.kong_ct_ids[conf_id] = nil
  end

  perf.git_restore()

  return true
end

local function inject_kong_admin_client(self, helpers)
  helpers.admin_client = function(timeout)
    if nkeys(self.kong_ct_ids) < 1 then
      error("helpers.admin_client can only be called after perf.start_kong")
    end

    -- find all kong containers with first one that exposes admin port
    for _, kong_id in pairs(kong.ct_ids) do
      local admin_port, err = get_container_port(kong_id, "8001/tcp")
      if err then
        error("failed to get kong admin port: " .. (err or "nil"))
      end
      if admin_port then
        return helpers.http_client("127.0.0.1", admin_port, timeout or 60000)
      end
      -- not admin_port, it's fine, maybe it's a dataplane
    end

    error("failed to get kong admin port from all Kong containers")
  end
  return helpers
end

function _M:setup()
  if not self.psql_ct_id then
    local cid, err = create_container(self, "-p5432 " ..
                    "-e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_DB=kong_tests " ..
                    "-e POSTGRES_USER=kong ",
                    "postgres:11",
                    "postgres -N 2333")
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

  perf.unsetenv("KONG_PG_PORT")

  return inject_kong_admin_client(self, helpers)
end

function _M:start_upstreams(conf, port_count)
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
  ngx.sleep(3) -- TODO: less flaky

  local worker_vip, err = get_container_vip(self.worker_ct_id)
  if err then
    return false, "unable to read worker container's private IP: " .. err
  end

  if not perf.wait_output("docker logs -f " .. self.worker_ct_id, " start worker process") then
    self.log.info("worker container logs:")
    perf.execute("docker logs " .. self.worker_ct_id, { logger = self.log.log_exec })
    return false, "timeout waiting worker(nginx) to start (5s)"
  end

  self.log.info("worker is started")

  local uris = {}
  for i=1,port_count do
    uris[i] = "http://" .. worker_vip .. ":" .. UPSTREAM_PORT+i-1
  end
  return uris
end

function _M:_hydrate_kong_configuration(kong_conf, driver_conf)
  local config = ''
  for k, v in pairs(kong_conf) do
    config = string.format("%s -e KONG_%s='%s'", config, k:upper(), v)
  end
  config = config .. " -e KONG_PROXY_ACCESS_LOG=/dev/null"

  -- adds database configuration
  if kong_conf['database'] == nil then
    config = config .. " --link " .. self.psql_ct_id .. ":postgres " ..
    "-e KONG_PG_HOST=postgres " ..
    "-e KONG_PG_DATABASE=kong_tests "
  end

  if driver_conf['dns'] ~= nil then
    for name, address in pairs(driver_conf['dns']) do
      config = string.format("%s --link %s:%s", config, address, name)
    end
  end

  for _, port in ipairs(driver_conf['ports']) do
    config = string.format("%s -p %d", config, port)
  end

  return config
end

function _M:start_kong(version, kong_conf, driver_conf)
  if not version then
    error("Kong version is not defined", 2)
  end

  local use_git
  local image = "kong"
  local kong_conf_id = driver_conf['container_id'] or 'default'

  if driver_conf['ports'] == nil then
    driver_conf['ports'] = { 8000 }
  end

  self.daily_image_desc = nil
  if version:startswith("git:") then
    perf.git_checkout(version:sub(#("git:")+1))
    use_git = true
    if self.opts.use_daily_image then
      image = "kong/kong"
      local tag, err = perf.get_newest_docker_tag(image, "ubuntu20.04")
      if not version then
        return nil, "failed to use daily image: " .. err
      end
      version = tag.name
      self.log.debug("daily image " .. tag.name .." was pushed at ", tag.last_updated)
    else
      version = perf.get_kong_version()
    end
    self.log.debug("current git hash resolves to docker version ", version)
  elseif version:match("rc") or version:match("beta") then
    image = "kong/kong"
  end

  if self.kong_ct_ids[kong_conf_id] == nil then
    local config = self:_hydrate_kong_configuration(kong_conf, driver_conf)
    local cid, err = create_container(self, config, image .. ":" .. version,
      "/bin/bash -c 'kong migrations up -y && kong migrations finish -y && /docker-entrypoint.sh kong docker-start'")
    if err then
      return false, "error running docker create when creating kong container: " .. err
    end
    self.kong_ct_ids[kong_conf_id] = cid
    perf.execute("docker cp ./spec/fixtures/kong_clustering.crt " .. cid .. ":/")
    perf.execute("docker cp ./spec/fixtures/kong_clustering.key " .. cid .. ":/")

    if use_git then
      perf.execute("docker cp ./kong " .. cid .. ":/usr/local/share/lua/5.1/")
    end
  end

  self.log.info("starting kong container with ID ", self.kong_ct_ids[kong_conf_id])
  local ok, err = start_container(self.kong_ct_ids[kong_conf_id])
  if not ok then
    return false, "kong is not running: " .. err
  end

  -- wait
  if not perf.wait_output("docker logs -f " .. self.kong_ct_ids[kong_conf_id], " start worker process") then
    self.log.info("kong container logs:")
    perf.execute("docker logs " .. self.kong_ct_ids[kong_conf_id], { logger = self.log.log_exec })
    return false, "timeout waiting kong to start (5s)"
  end

  local ports = driver_conf['ports']
  local port_maps = {}
  for _, port in ipairs(ports) do
    local mport, err = get_container_port(self.kong_ct_ids[kong_conf_id], port .. "/tcp")
    if not mport then
      return false, "can't find exposed port " .. port .. " for kong " ..
            self.kong_ct_ids[kong_conf_id] .. " :" .. err
    end
    table.insert(port_maps, string.format("%s->%s/tcp", mport, port))
  end

  self.log.info("kong is started to listen at port ", table.concat(port_maps, ", "))
  return self.kong_ct_ids[kong_conf_id]
end

function _M:stop_kong()
  for conf_id, kong_ct_id in pairs(self.kong_ct_ids) do
    if not perf.execute("docker stop " .. kong_ct_id) then
      return false
    end
  end

  return true
end

function _M:get_start_load_cmd(stub, script, uri, kong_id)
  if not uri then
    if not kong_id then
      kong_id = self.kong_ct_ids[next(self.kong_ct_ids)] -- pick the first one
    end
    local kong_vip, err = get_container_vip(kong_id)
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

function _M:get_admin_uri(kong_id)
  if not kong_id then
    kong_id = self.kong_ct_ids[next(self.kong_ct_ids)] -- pick the first one
  end
  local kong_vip, err = get_container_vip(kong_id)
  if err then
    return false, "unable to read kong container's private IP: " .. err
  end

  return string.format("http://%s:8001", kong_vip)
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
  for _, kong_ct_id in pairs(self.kong_ct_ids) do
    perf.execute("docker logs " .. kong_ct_id .. " 2>'" .. path .. "-" .. kong_ct_id .. "'",
                 { logger = self.log.log_exec })
  end
  return true
end

function _M:save_pgdump(path)
  if not self.psql_ct_id then
    return false, "postgres container not started"
  end

  return perf.execute("docker exec -i " ..  self.psql_ct_id .. " pg_dump -Ukong kong_tests --data-only >'" .. path .. "'",
                 { logger = self.log.log_exec })
end

function _M:load_pgdump(path, dont_patch_service)
  if not self.psql_ct_id then
    return false, "postgres container not started"
  end

  local _, err = perf.execute("cat " .. path .. " |docker exec -i " ..  self.psql_ct_id .. " psql -Ukong kong_tests",
                 { logger = self.log.log_exec })
  if err then
    return false, err
  end

  if dont_patch_service then
    return true
  end

  if not self.worker_ct_id then
    return false, "worker not started, can't patch_service; call start_upstream first"
  end

  local worker_vip, err = get_container_vip(self.worker_ct_id)
  if err then
    return false, "unable to read worker container's private IP: " .. err
  end

  return perf.execute("echo \"UPDATE services set host='" .. worker_vip ..
          "', port=" .. UPSTREAM_PORT ..
          ", protocol='http';\" | docker exec -i " ..  self.psql_ct_id .. " psql -Ukong kong_tests",
          { logger = self.log.log_exec })
end

function _M:get_based_version()
  return self.daily_image_desc or perf.get_kong_version()
end

return _M
