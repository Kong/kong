-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong = kong
local sub = string.sub
local timer_at = ngx.timer.at
local split = require('kong.tools.utils').split
local random = math.random

local is_http = ngx.config.subsystem == "http"
local metrics = {}


local function refresh_entity_counts(premature, delay)
  if premature then
    return
  end

  if not metrics.db_entities then
    return
  end

  local counters = require "kong.workspaces.counters"

  local counts, err = counters.entity_counts()

  if err then
    kong.log.err("failed retrieving entity counts: ", err)

    -- clear out existing metrics so that we aren't emitting any potentially
    -- stale data
    metrics.db_entities:reset()
    metrics.db_entity_count_errors:inc()

  elseif counts then
    local total = 0
    for _, count in pairs(counts) do
      total = total + count
    end
    metrics.db_entities:set(total)
  end

  -- apply some jitter at each re-schedule to spread out DB load
  local next_run = delay + random(10)

  local ok
  ok, err = timer_at(next_run, refresh_entity_counts, delay)
  if not ok then
    metrics.db_entity_count_errors:inc()
    kong.log.alert("failed to schedule entity count metric refresh: ", err)
  end
end


local function init(prometheus)
  metrics.license_errors = prometheus:counter("enterprise_license_errors",
                                              "Errors when collecting license info")
  metrics.license_signature = prometheus:gauge("enterprise_license_signature",
                                              "Last 32 bytes of the license signature in number")
  metrics.license_expiration = prometheus:gauge("enterprise_license_expiration",
                                                "Unix epoch time when the license expires, " ..
                                                "the timestamp is substracted by 24 hours "..
                                                "to avoid difference in timezone")
  metrics.license_features = prometheus:gauge("enterprise_license_features",
                                                "License features features",
                                              { "feature" })

  prometheus.dict:set("enterprise_license_errors", 0)

  local role = kong.configuration.role
  local strategy = kong.configuration.database

  -- Entity counts are "global" and not really specific to any subsystem,
  -- so without this gate we would just be measuring the same metric twice
  -- (once in http land, once in stream land).
  --
  -- We also don't initialize the entity counter hooks in db-less/data_plane
  -- mode, so we cannot expose the entity counter metrics in that case.
  if is_http and role ~= "data_plane" and strategy ~= "off" then
    metrics.db_entities = prometheus:gauge("db_entities_total",
                                           "Total number of Kong db entities")
    metrics.db_entity_count_errors = prometheus:counter(
      "db_entity_count_errors",
      "Errors during entity count collection"
    )
    prometheus.dict:set("db_entity_count_errors", 0)
  end
end

local function license_date_to_unix(yyyy_mm_dd)
  local date_t = split(yyyy_mm_dd, "-")

  local ok, res = pcall(os.time, {
    year = tonumber(date_t[1]),
    month = tonumber(date_t[2]),
    day = tonumber(date_t[3])
  })
  if ok then
    return res
  end

  return nil, res
end

local function metric_data()
  if not metrics then
    kong.log.err("prometheus: plugin is not initialized, please make sure ",
                 " 'prometheus_metrics' shared dict is present in nginx template")
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  if not kong.license or not kong.license.license then
    metrics.license_errors:inc()
    kong.log.err("cannot read kong.license when collecting license info")
    return
  end

  local lic = kong.license.license

  if tonumber(lic.version) ~= 1 then
    metrics.license_errors:inc()
    kong.log.err("enterprise license version (" .. (lic.version or "nil") .. ") unsupported")
    return
  end

  local sig = lic.signature
  if not sig then
    metrics.license_errors:inc()
    kong.log.err("cannot read license signature when collecting license info")
    return
  end
  -- last 32 bytes as an int32
  metrics.license_signature:set(tonumber("0x" .. sub(sig, #sig-33, #sig)))

  local expiration = lic.payload and lic.payload.license_expiration_date
  if not expiration then
    metrics.license_errors:inc()
    kong.log.err("cannot read license expiration when collecting license info")
    return
  end
  local tm, err = license_date_to_unix(expiration)
  if not tm then
    metrics.license_errors:inc()
    kong.log.err("cannot parse license expiration when collecting license info ", err)
    return
  end
  -- substract it by 24h so everyone one earth is happy monitoring it
  metrics.license_expiration:set(tm - 86400)


  metrics.license_features:set(kong.licensing:allow_ee_entity("READ") and 1 or 0,
                              { "ee_entity_read" })
  metrics.license_features:set(kong.licensing:allow_ee_entity("WRITE") and 1 or 0,
                              { "ee_entity_write" })
end

local function init_worker()
  -- schedule the entity count refresh timer
  --
  -- The entity count metric is just a measurement of some db values, so
  -- there's no reason to execute this recurring task on more than one NGINX
  -- worker process.
  if ngx.worker.id() == 0 and metrics.db_entities then
    -- perform the initial refresh ASAP and once perminute after that
    local ok, err = timer_at(0, refresh_entity_counts, 60)
    if not ok then
      metrics.db_entity_count_errors:inc()
      kong.log.alert("failed to schedule entity count metric refresh: ", err)
    end
  end
end

return {
  init        = init,
  metric_data = metric_data,
  init_worker = init_worker,
}
