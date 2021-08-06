local kong = kong
local ngx = ngx
local find = string.find
local lower = string.lower
local concat = table.concat
local select = select
local balancer = require("kong.runloop.balancer")
local get_all_upstreams = balancer.get_all_upstreams
if not balancer.get_all_upstreams then -- API changed since after Kong 2.5
  get_all_upstreams = require("kong.runloop.balancer.upstreams").get_all_upstreams
end

local CLUSTERING_SYNC_STATUS = require("kong.constants").CLUSTERING_SYNC_STATUS

local stream_available, stream_api = pcall(require, "kong.tools.stream_api")

local role = kong.configuration.role

local DEFAULT_BUCKETS = { 1, 2, 5, 7, 10, 15, 20, 25, 30, 40, 50, 60, 70,
                          80, 90, 100, 200, 300, 400, 500, 1000,
                          2000, 5000, 10000, 30000, 60000 }
local metrics = {}
-- prometheus.lua instance
local prometheus

-- use the same counter library shipped with Kong
package.loaded['prometheus_resty_counter'] = require("resty.counter")

local enterprise
local pok = pcall(require, "kong.enterprise_edition.licensing")
if pok then
  enterprise = require("kong.plugins.prometheus.enterprise.exporter")
end

local kong_subsystem = ngx.config.subsystem

local function init()
  local shm = "prometheus_metrics"
  if not ngx.shared.prometheus_metrics then
    kong.log.err("prometheus: ngx shared dict 'prometheus_metrics' not found")
    return
  end

  prometheus = require("kong.plugins.prometheus.prometheus").init(shm, "kong_")

  -- global metrics
  if kong_subsystem == "http" then
    metrics.connections = prometheus:gauge("nginx_http_current_connections",
      "Number of HTTP connections",
      {"state"})
  else
    metrics.connections = prometheus:gauge("nginx_stream_current_connections",
      "Number of Stream connections",
      {"state"})
  end
  metrics.db_reachable = prometheus:gauge("datastore_reachable",
                                          "Datastore reachable from Kong, " ..
                                          "0 is unreachable")
  metrics.upstream_target_health = prometheus:gauge("upstream_target_health",
                                          "Health status of targets of upstream. " ..
                                          "States = healthchecks_off|healthy|unhealthy|dns_error, " ..
                                          "value is 1 when state is populated.",
                                          {"upstream", "target", "address", "state"})

  local memory_stats = {}
  memory_stats.worker_vms = prometheus:gauge("memory_workers_lua_vms_bytes",
                                             "Allocated bytes in worker Lua VM",
                                             {"pid", "kong_subsystem"})
  memory_stats.shms = prometheus:gauge("memory_lua_shared_dict_bytes",
                                       "Allocated slabs in bytes in a shared_dict",
                                       {"shared_dict", "kong_subsystem"})
  memory_stats.shm_capacity = prometheus:gauge("memory_lua_shared_dict_total_bytes",
                                               "Total capacity in bytes of a shared_dict",
                                               {"shared_dict", "kong_subsystem"})

  local res = kong.node.get_memory_stats()
  for shm_name, value in pairs(res.lua_shared_dicts) do
    memory_stats.shm_capacity:set(value.capacity, { shm_name, kong_subsystem })
  end

  metrics.memory_stats = memory_stats

  -- per service/route
  if kong_subsystem == "http" then
    metrics.status = prometheus:counter("http_status",
                                        "HTTP status codes per service/route in Kong",
                                        {"service", "route", "code"})
  else
    metrics.status = prometheus:counter("stream_status",
                                        "Stream status codes per service/route in Kong",
                                        {"service", "route", "code"})
  end
  metrics.latency = prometheus:histogram("latency",
                                         "Latency added by Kong, total " ..
                                         "request time and upstream latency " ..
                                         "for each service/route in Kong",
                                         {"service", "route", "type"},
                                         DEFAULT_BUCKETS) -- TODO make this configurable
  metrics.bandwidth = prometheus:counter("bandwidth",
                                         "Total bandwidth in bytes " ..
                                         "consumed per service/route in Kong",
                                         {"service", "route", "type"})
  metrics.consumer_status = prometheus:counter("http_consumer_status",
                                          "HTTP status codes for customer per service/route in Kong",
                                          {"service", "route", "code", "consumer"})

  if enterprise then
    enterprise.init(prometheus)
  end


  -- Hybrid mode status
  if role == "control_plane" then
    metrics.data_plane_last_seen = prometheus:gauge("data_plane_last_seen",
                                              "Last time data plane contacted control plane",
                                              {"node_id", "hostname", "ip"})
    metrics.data_plane_config_hash = prometheus:gauge("data_plane_config_hash",
                                              "Config hash numeric value of the data plane",
                                              {"node_id", "hostname", "ip"})

    metrics.data_plane_version_compatible = prometheus:gauge("data_plane_version_compatible",
                                              "Version compatible status of the data plane, 0 is incompatible",
                                              {"node_id", "hostname", "ip", "kong_version"})
  end
end

local function init_worker()
  prometheus:init_worker()
end

-- Convert the MD5 hex string to its numeric representation
-- Note the following will be represented as a float instead of int64 since luajit
-- don't like int64. Good news is prometheus uses float instead of int64 as well
local function config_hash_to_number(hash_str)
  return tonumber("0x" .. hash_str)
end

-- Since in the prometheus library we create a new table for each diverged label
-- so putting the "more dynamic" label at the end will save us some memory
local labels_table = {0, 0, 0}
local labels_table4 = {0, 0, 0, 0}
local upstream_target_addr_health_table = {
  { value = 0, labels = { 0, 0, 0, "healthchecks_off" } },
  { value = 0, labels = { 0, 0, 0, "healthy" } },
  { value = 0, labels = { 0, 0, 0, "unhealthy" } },
  { value = 0, labels = { 0, 0, 0, "dns_error" } },
}

local function set_healthiness_metrics(table, upstream, target, address, status, metrics_bucket)
  for i = 1, #table do
    table[i]['labels'][1] = upstream
    table[i]['labels'][2] = target
    table[i]['labels'][3] = address
    table[i]['value'] = (status == table[i]['labels'][4]) and 1 or 0
    metrics_bucket:set(table[i]['value'], table[i]['labels'])
  end
end


local log

if kong_subsystem == "http" then
  function log(message, serialized)
    if not metrics then
      kong.log.err("prometheus: can not log metrics because of an initialization "
              .. "error, please make sure that you've declared "
              .. "'prometheus_metrics' shared dict in your nginx template")
      return
    end

    local service_name
    if message and message.service then
      service_name = message.service.name or message.service.host
    else
      -- do not record any stats if the service is not present
      return
    end

    local route_name
    if message and message.route then
      route_name = message.route.name or message.route.id
    end

    labels_table[1] = service_name
    labels_table[2] = route_name
    labels_table[3] = message.response.status
    metrics.status:inc(1, labels_table)

    local request_size = tonumber(message.request.size)
    if request_size and request_size > 0 then
      labels_table[3] = "ingress"
      metrics.bandwidth:inc(request_size, labels_table)
    end

    local response_size = tonumber(message.response.size)
    if response_size and response_size > 0 then
      labels_table[3] = "egress"
      metrics.bandwidth:inc(response_size, labels_table)
    end

    local request_latency = message.latencies.request
    if request_latency and request_latency >= 0 then
      labels_table[3] = "request"
      metrics.latency:observe(request_latency, labels_table)
    end

    local upstream_latency = message.latencies.proxy
    if upstream_latency ~= nil and upstream_latency >= 0 then
      labels_table[3] = "upstream"
      metrics.latency:observe(upstream_latency, labels_table)
    end

    local kong_proxy_latency = message.latencies.kong
    if kong_proxy_latency ~= nil and kong_proxy_latency >= 0 then
      labels_table[3] = "kong"
      metrics.latency:observe(kong_proxy_latency, labels_table)
    end

    if serialized.consumer ~= nil then
      labels_table4[1] = labels_table[1]
      labels_table4[2] = labels_table[2]
      labels_table4[3] = message.response.status
      labels_table4[4] = serialized.consumer
      metrics.consumer_status:inc(1, labels_table4)
    end
  end

else
  function log(message)
    if not metrics then
      kong.log.err("prometheus: can not log metrics because of an initialization "
              .. "error, please make sure that you've declared "
              .. "'prometheus_metrics' shared dict in your nginx template")
      return
    end

    local service_name
    if message and message.service then
      service_name = message.service.name or message.service.host
    else
      -- do not record any stats if the service is not present
      return
    end

    local route_name
    if message and message.route then
      route_name = message.route.name or message.route.id
    end

    labels_table[1] = service_name
    labels_table[2] = route_name
    labels_table[3] = message.session.status
    metrics.status:inc(1, labels_table)

    local ingress_size = tonumber(message.session.received)
    if ingress_size and ingress_size > 0 then
      labels_table[3] = "ingress"
      metrics.bandwidth:inc(ingress_size, labels_table)
    end

    local egress_size = tonumber(message.session.sent)
    if egress_size and egress_size > 0 then
      labels_table[3] = "egress"
      metrics.bandwidth:inc(egress_size, labels_table)
    end

    local session_latency = message.latencies.session
    if session_latency and session_latency >= 0 then
      labels_table[3] = "request"
      metrics.latency:observe(session_latency, labels_table)
    end

    local kong_proxy_latency = message.latencies.kong
    if kong_proxy_latency ~= nil and kong_proxy_latency >= 0 then
      labels_table[3] = "kong"
      metrics.latency:observe(kong_proxy_latency, labels_table)
    end
  end
end


local function metric_data()
  if not prometheus or not metrics then
    kong.log.err("prometheus: plugin is not initialized, please make sure ",
                 " 'prometheus_metrics' shared dict is present in nginx template")
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  if ngx.location then
    local r = ngx.location.capture "/nginx_status"

    if r.status ~= 200 then
      kong.log.warn("prometheus: failed to retrieve /nginx_status ",
        "while processing /metrics endpoint")

    else
      local accepted, handled, total = select(3, find(r.body,
        "accepts handled requests\n (%d*) (%d*) (%d*)"))
      metrics.connections:set(accepted, { "accepted" })
      metrics.connections:set(handled, { "handled" })
      metrics.connections:set(total, { "total" })
    end
  end

  metrics.connections:set(ngx.var.connections_active or 0, { "active" })
  metrics.connections:set(ngx.var.connections_reading or 0, { "reading" })
  metrics.connections:set(ngx.var.connections_writing or 0, { "writing" })
  metrics.connections:set(ngx.var.connections_waiting or 0, { "waiting" })

  -- db reachable?
  local ok, err = kong.db.connector:connect()
  if ok then
    metrics.db_reachable:set(1)

  else
    metrics.db_reachable:set(0)
    kong.log.err("prometheus: failed to reach database while processing",
                 "/metrics endpoint: ", err)
  end

  -- erase all target/upstream metrics, prevent exposing old metrics
  metrics.upstream_target_health:reset()

  -- upstream targets accessible?
  local upstreams_dict = get_all_upstreams()
  for key, upstream_id in pairs(upstreams_dict) do
    local _, upstream_name = key:match("^([^:]*):(.-)$")
    upstream_name = upstream_name and upstream_name or key
    -- based on logic from kong.db.dao.targets
    local health_info
    health_info, err = balancer.get_upstream_health(upstream_id)
    if err then
      kong.log.err("failed getting upstream health: ", err)
    end

    if health_info then
      for target_name, target_info in pairs(health_info) do
        if target_info ~= nil and target_info.addresses ~= nil and
          #target_info.addresses > 0 then
          -- healthchecks_off|healthy|unhealthy
          for _, address in ipairs(target_info.addresses) do
            local address_label = concat({address.ip, ':', address.port})
            local status = lower(address.health)
            set_healthiness_metrics(upstream_target_addr_health_table, upstream_name, target_name, address_label, status, metrics.upstream_target_health)
          end
        else
          -- dns_error
          set_healthiness_metrics(upstream_target_addr_health_table, upstream_name, target_name, '', 'dns_error', metrics.upstream_target_health)
        end
      end
    end
  end

  -- memory stats
  local res = kong.node.get_memory_stats()
  for shm_name, value in pairs(res.lua_shared_dicts) do
    metrics.memory_stats.shms:set(value.allocated_slabs, { shm_name, kong_subsystem })
  end
  for i = 1, #res.workers_lua_vms do
    metrics.memory_stats.worker_vms:set(res.workers_lua_vms[i].http_allocated_gc,
                                        { res.workers_lua_vms[i].pid, kong_subsystem })
  end

  if enterprise then
    enterprise.metric_data()
  end

  -- Hybrid mode status
  if role == "control_plane" then
    -- Cleanup old metrics
    metrics.data_plane_last_seen:reset()
    metrics.data_plane_config_hash:reset()

    for data_plane, err in kong.db.clustering_data_planes:each() do
      if err then
        kong.log.err("failed to list data planes: ", err)
        goto next_data_plane
      end

      local labels = { data_plane.id, data_plane.hostname, data_plane.ip }

      metrics.data_plane_last_seen:set(data_plane.last_seen, labels)
      metrics.data_plane_config_hash:set(config_hash_to_number(data_plane.config_hash), labels)

      labels[4] = data_plane.version
      local compatible = 1

      if data_plane.sync_status == CLUSTERING_SYNC_STATUS.KONG_VERSION_INCOMPATIBLE
        or data_plane.sync_status == CLUSTERING_SYNC_STATUS.PLUGIN_SET_INCOMPATIBLE
        or data_plane.sync_status == CLUSTERING_SYNC_STATUS.PLUGIN_VERSION_INCOMPATIBLE then

        compatible = 0
      end
      metrics.data_plane_version_compatible:set(compatible, labels)

::next_data_plane::
    end
  end

  return prometheus:metric_data()
end

local function collect(with_stream)
  ngx.header["Content-Type"] = "text/plain; charset=UTF-8"

  ngx.print(metric_data())

  -- only gather stream metrics if stream_api module is avaiable
  -- and user has configured at least one stream listeners
  if stream_available and #kong.configuration.stream_listeners > 0 then
    local res, err = stream_api.request("prometheus", "")
    if err then
      kong.log.err("failed to collect stream metrics: ", err)
    else
      ngx.print(res)
    end
  end
end

local function get_prometheus()
  if not prometheus then
    kong.log.err("prometheus: plugin is not initialized, please make sure ",
                     " 'prometheus_metrics' shared dict is present in nginx template")
  end
  return prometheus
end

return {
  init        = init,
  init_worker = init_worker,
  log         = log,
  metric_data = metric_data,
  collect     = collect,
  get_prometheus = get_prometheus,
}
