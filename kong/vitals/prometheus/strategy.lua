-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local fmt        = string.format
local sub        = string.sub
local math_min   = math.min
local math_max   = math.max
local math_huge  = math.huge
local math_floor = math.floor
local log        = ngx.log
local DEBUG      = ngx.DEBUG
local WARN       = ngx.WARN



local pl_stringx   = require "pl.stringx"
local statsd_handler = require "kong.vitals.prometheus.statsd.handler"
local vitals_utils = require "kong.vitals.utils"

local http = require "resty.http"
local cjson = require "cjson.safe"
local new_tab = require "table.new"
local null = cjson.null -- or ngx.null
local table_insert = table.insert
local table_concat = table.concat
local ngx_escape_uri = ngx.escape_uri
local ngx_time = ngx.time


local _log_prefix = "[vitals-strategy] "

local _M = { }

local mt = {
  __index = function(_, k, ...)
    local v = _M[k]
    if v ~= nil then
      return v
    end
    -- shouldn't go here, needs to add dummy functions in this module
    log(DEBUG, _log_prefix, fmt("function %s is not implemented for \"prometheus\" strategy\"", k))
    return function(...)
      return true, nil
    end
  end
}

function _M.select_phone_home()
  return {}, nil
end

function _M.node_exists()
  return true, nil
end

-- @param value The options string to check for flags (whitespace separated)
-- @param flags List of boolean flags to check for.
-- @returns 1) remainder string after all flags removed, 2) table with flag
-- booleans, 3) sanitized flags string
local function parse_option_flags(value, flags)
  assert(type(value) == "string")

  value = " " .. value .. " "

  local sanitized = ""
  local result = {}

  for _, flag in ipairs(flags) do
    local count
    local patt = "%s" .. flag .. "%s"

    value, count = value:gsub(patt, " ")

    if count > 0 then
      result[flag] = true
      sanitized = sanitized .. " " .. flag

    else
      result[flag] = false
    end
  end

  return pl_stringx.strip(value), result, pl_stringx.strip(sanitized)
end


function _M.new(_, opts)
  if not opts then
    opts = {
      host = "127.0.0.1",
      port = 9090
    }
  end

  local custom_filters_str = opts.custom_filters or ""

  local aggregator_str = ""
  if not opts.cluster_level then
    aggregator_str = " by (instance)"
  end

  local common_stats_metrics = {
    -- { label_name_to_be_returned, query string, is_rate }
    { "cache_datastore_hits_total", fmt("sum%s(kong_cache_datastore_hits_total{%s})",
      aggregator_str, custom_filters_str), true },
    { "cache_datastore_misses_total", fmt("sum%s(kong_cache_datastore_misses_total{%s})",
      aggregator_str, custom_filters_str), true },
    { "latency_proxy_request_min_ms", fmt("min%s(kong_latency_proxy_request_min{%s})",
      aggregator_str, custom_filters_str) },
    { "latency_proxy_request_max_ms", fmt("max%s(kong_latency_proxy_request_max{%s})",
      aggregator_str, custom_filters_str) },
    { "latency_upstream_min_ms", fmt("min%s(kong_latency_upstream_min{%s})",
      aggregator_str, custom_filters_str) },
    { "latency_upstream_max_ms", fmt("max%s(kong_latency_upstream_max{%s})",
      aggregator_str, custom_filters_str) },
    { "requests_proxy_total", fmt("sum%s(kong_requests_proxy{%s})",
      aggregator_str, custom_filters_str), true },
    { "latency_proxy_request_avg_ms",
      fmt("sum%s(rate(kong_latency_proxy_request_sum{%s}[1m])) / sum%s(rate(kong_latency_proxy_request_count{%s}[1m])) * 1000",
        aggregator_str, custom_filters_str, aggregator_str, custom_filters_str) }, -- we only have minute level precision
    { "latency_upstream_avg_ms",
      fmt("sum%s(rate(kong_latency_upstream_sum{%s}[1m])) / sum%s(rate(kong_latency_upstream_count{%s}[1m])) * 1000",
        aggregator_str, custom_filters_str, aggregator_str, custom_filters_str) },
  }

  local self = {
    host                 = opts.host,
    port                 = tonumber(opts.port),
    connection_timeout   = tonumber(opts.connection_timeout) or 5000, -- 5s
    custom_filters_str   = custom_filters_str,
    has_custom_filters   = #custom_filters_str > 0,
    scrape_interval      = tonumber(opts.scrape_interval) or 15,
    common_stats_metrics = common_stats_metrics,
    headers              = { Authorization = opts.auth_header },
    cluster_level        = opts.cluster_level or false,
    statsd_config        = { },
  }

  return setmetatable(self, mt)
end

function _M:init()
  local conf = kong.configuration

  -- hostname is statsd_address as each one should be a sidecar to every kong node
  local host, port, use_tcp
  local remainder, _, protocol = parse_option_flags(conf.vitals_statsd_address, { "udp", "tcp" })
  if remainder then
    host, port = remainder:match("(.+):([%d]+)$")
    port = tonumber(port)
    if not host or not port then
      host = remainder:match("(unix:/.+)$")
      port = nil
    end
  end
  use_tcp = protocol == "tcp"

  local statsd_config = {
    host = host,
    port = port,
    prefix = conf.vitals_statsd_prefix,
    use_tcp = use_tcp,
    udp_packet_size = conf.vitals_statsd_udp_packet_size or 0,
    metrics = {
      { name = "request_count", sample_rate = 1, stat_type = "counter", service_identifier = "service_id" },
      { name = "status_count", sample_rate = 1, stat_type = "counter", service_identifier = "service_id" },
      { name = "upstream_latency", stat_type = "timer", service_identifier = "service_id" },
      { name = "kong_latency", stat_type = "timer", service_identifier = "service_id" },
      { name = "status_count_per_user", sample_rate = 1, consumer_identifier = "consumer_id",
        stat_type = "counter", service_identifier = "service_id" },
      { name = "status_count_per_workspace", sample_rate = 1, stat_type = "counter",
        workspace_identifier = "workspace_id", service_identifier = "service_id" },
      { name = "status_count_per_user_per_route", sample_rate = 1, consumer_identifier = "consumer_id",
        stat_type = "counter", service_identifier = "service_id" },
      { name = "cache_datastore_misses_total", sample_rate = 1, stat_type = "counter",
        service_identifier = "service_id" },
      { name = "cache_datastore_hits_total", sample_rate = 1, stat_type = "counter",
        service_identifier = "service_id" },
      { name = "shdict_usage", sample_rate = 1, stat_type = "gauge", service_identifier = "service_id" },
    },
  }

  local handler, err = statsd_handler.new(statsd_config)
  if err then
    return false, err
  end

  self.statsd_handler = handler
  return true, nil
end

-- no-op interface methods for handling runtime changes for vitals
function _M:start()
  return true
end
function _M:stop()
  return true
end

function _M:interval_width(level)
  return vitals_utils.interval_to_duration[level]
end

function _M:query(start_ts, metrics_query, interval)
  start_ts = tonumber(start_ts)
  if not start_ts then
    return nil, "expect first paramter to be a number"
  end

  if type(metrics_query) ~= "table" then
    return nil, "expect second paramter to be a table"
  end

  -- resty.http can only be initialized per request
  local client, err = http.new()
  if not client then
    return nil, "error initializing resty http: " .. err
  end

  client:set_timeout(self.connection_timeout)

  local _, err = client:connect(self.host, self.port)

  if err then
    return nil, "error connecting Prometheus: " .. err
  end

  local stats = {}

  local end_ts = ngx_time()
  if start_ts >= end_ts then
    return nil, "expect first parameter to be a timestamp in the past"
  end

  -- round to nearest next interval
  end_ts = end_ts - end_ts % interval + interval
  -- round to nearest previous interval
  start_ts = start_ts - start_ts % interval - interval


  for i, q in ipairs(metrics_query) do
    local res, err = client:request {
        method = "GET",
        path = "/api/v1/query_range?query=" ..  ngx_escape_uri(q[2]) .. "&start=" .. start_ts
                  .. "&end=" .. end_ts .. "&step=" .. interval .. "s",
        headers = self.headers,
    }
    if not res then
      return nil, "request Prometheus failed: " .. err
    end

    local body, err = res:read_body()
    if not body then
      return nil, "read Prometheus response failed: " .. err
    end

    local stat, err = cjson.decode(body)

    if not stat then
      return nil, "json decode failed " .. err
    elseif stat.status ~= "success" then
      return nil, "Prometheus reported " .. stat.errorType .. ": " .. stat.error
    end

    stats[i] = stat.data.result
  end

  client:set_keepalive()

  return stats, nil, end_ts - start_ts
end


-- Converts common metrics from prometheus format to vitals format
-- @param[type=table] metrics_query A table containing expected labels and prometheus query strings
-- @param[type=table] prometheus_stats Json-decoded array returned from prometheus
-- @param[type=number] interval The datapoint step
-- @param[type=number] duration_seconds The time range of query
-- @param[type=boolean] aggregate If we are showing cluster metrics or not, only influence the meta.level value, there won't be any aggregation
-- @return A table in vitals format
local function translate_vitals_stats(metrics_query, prometheus_stats, interval, duration_seconds, aggregate)
  local metrics_count = #metrics_query

  local ret = {
    meta = {
      nodes = {},
      stat_labels = new_tab(metrics_count, 0)
    },
    stats = {},
  }


  ret.meta.interval = vitals_utils.duration_to_interval[interval]

  ret.meta.interval_width = interval

  if aggregate then
    ret.meta.level = "cluster"
  else
    ret.meta.level = "node"
  end

  local earliest_ts = 0xFFFFFFFF
  local latest_ts = 0

  local node_stats = ret.stats
  local last_metric_name
  local expected_dp_count = duration_seconds / interval
  for idx, series_list in ipairs(prometheus_stats) do
    local metric_name = metrics_query[idx][1]
    if last_metric_name ~= metric_name then
      last_metric_name = metric_name
      table_insert(ret.meta.stat_labels, metric_name)
    end

    local is_rate = metrics_query[idx][3]

    local series_not_empty = false
    for series_idx, series in ipairs(series_list) do
      -- if not translate results with aggregate=true, make sure every metrics is aggreated to one time series
      if series_idx > 1 and aggregate then
        log(WARN, _log_prefix, "metrics ", metric_name, " has ", series_idx, " series, may be it's not correctly aggregated?")
        break
      end

      series_not_empty = true
      -- Add to meta,nodes
      local host
      if aggregate then
        host = "cluster"
      else
        host = series.metric.instance
      end

      if not node_stats[host] then
        node_stats[host] = new_tab(0, expected_dp_count)
        ret.meta.nodes[host] = { hostname = host }
      end

      local dps = series.values

      local n = node_stats[host]
      local start_k, current_earliest_ts, current_latest_ts

      current_earliest_ts = dps[1][1]
      current_latest_ts = dps[#dps][1]

      earliest_ts = math_min(earliest_ts, current_earliest_ts)
      latest_ts = math_max(latest_ts, current_latest_ts)
      -- add empty data points
      for ts = earliest_ts, current_earliest_ts - 1, interval do
        -- key should always be string, as we inserted them as string
        ts = tostring(ts)
        if not n[ts] then
          n[ts] = {}
        end
        -- add empty data points for other metrics that didn't reached this timestamp
        for i = #n[ts] + 1, #ret.meta.stat_labels, 1 do
          n[ts][i] = null
        end
      end

      for ts = current_latest_ts + 1, latest_ts, interval do
        -- key should always be string, as we inserted them as string
        ts = tostring(ts)
        if not n[ts] then
          n[ts] = {}
        end
        -- add empty data points for other metrics that didn't reached this timestamp
        for i = #n[ts] + 1, #ret.meta.stat_labels, 1 do
          n[ts][i] = null
        end
      end

      local last_value, last_ts
      start_k = earliest_ts
      for _, dp in ipairs(dps) do
        local current_value
        -- if we use integer as key, cjson will complain excessively sparse array
        local k = fmt("%d", dp[1])
        -- 'NaN' will be parsed to math.nan and cjson will not encode it
        local v = tonumber(dp[2])
        -- See http://lua-users.org/wiki/InfAndNanComparisons
        -- cjson also won't encode inf and -inf
        if v ~= v or v == math_huge or v == -math_huge then
          v = nil
        end

        if is_rate and v ~= nil then
          -- if there's missed scrape, skip the current for calculating rate
          -- because we have zero knowledge with the previous counter value
          if last_ts and dp[1] - last_ts > interval then
            last_value = nil
          end
          -- only it's not the first data point at beginning or missed scrape
          if last_value ~= nil then
            -- add the data point
            if last_value > v then -- detect counter reset
              current_value = v
            else
              current_value = v - last_value
            end
          end
        else
          current_value = v == nil and null or math_floor(v)
        end
        last_value = v
        last_ts = dp[1]

        -- if there's only one metric, client expect every timestamp has a value of number
        if metrics_count == 1 then
          -- current_value is nil when is_rate = true and is the first datapoint
          if current_value ~= nil then
            -- add the real data point
            n[k] = current_value
          end
        -- client expect every timestamp has a value of array
        else
          while k - start_k > interval do
            start_k = tostring(start_k + interval)
            if not n[start_k] then
              n[start_k] = {}
            end
            -- add empty data points for other metrics that didn't reached this timestamp
            for i = #n[start_k] + 1, #ret.meta.stat_labels, 1 do
              n[start_k][i] = null
            end
          end

          if not n[k] then
            n[k] = {}
          end
          -- add empty placeholder for other metrics
          for i = #n[k] + 1, #ret.meta.stat_labels - 1, 1 do
            n[k][i] = null
          end
          -- current_value is nil when is_rate = true and is the first datapoint
          if current_value ~= nil then
            -- add the real data point
            n[k][#n[k] + 1] = current_value
          end
        end

        start_k = k

      end -- for series_idx, series in ipairs(series_list) do

    end -- for idx, series in ipairs(prometheus_stats) do

    if not series_not_empty then
      log(DEBUG, _log_prefix, "metrics ", metric_name, " has no series")
    end

  end

  ret.meta.earliest_ts = earliest_ts
  ret.meta.latest_ts = latest_ts

  return ret, nil
end


-- Converts status codes metrics from prometheus format to vitals format
-- @param[type=table] metrics_query A table containing expected labels and prometheus query strings
-- @param[type=table] prometheus_stats Json-decoded array returned from prometheus
-- @param[type=number] interval The datapoint step
-- @param[type=number] duration_seconds The time range of query
-- @param[type=boolean] aggregate If we are showing cluster metrics or not, only influence the meta.level value, there won't be any aggregation
-- @param[type=boolean] merge_status_class If we are showing "2xx" instead of "200", "201"
-- @param[type=string] key_by (optional) Group result by the value of this label
-- @return A table in vitals format
local function translate_vitals_status(metrics_query, prometheus_stats, interval, duration_seconds, aggregate, merge_status_class, key_by)
  local ret = {
    meta = {
      nodes = {},
      stat_labels = {}
    },
    stats = {},
  }

  ret.meta.interval = vitals_utils.duration_to_interval[interval]
  ret.meta.interval_width = interval

  if aggregate then
    ret.meta.level = "cluster"
  else
    ret.meta.level = "node"
  end
  local stats = ret.stats
  local stat_labels_inserted = false
  local expected_dp_count = duration_seconds / interval
  -- we only has one query
  for idx, series in ipairs(prometheus_stats[1]) do
    if not stat_labels_inserted then
      local metric_name = metrics_query[idx][1]
      table_insert(ret.meta.stat_labels, metric_name)
      stat_labels_inserted = true
    end

    local n
    if not key_by then
      -- default by host name
      -- Add to meta,nodes
      -- TODO: change according to exporter tags
      local host = nil -- agg.tags.instance
      -- TODO: cluster type
      if aggregate then
        host = "cluster"
      end
      if not stats[host] then
        stats[host] = new_tab(0, expected_dp_count)
        ret.meta.nodes[host] = { hostname = host }
      end
      n = stats[host]
    else
      local tag_value = series.metric[key_by]
      if tag_value == nil then
        -- FIXME: broken metrics or old statsd rules? ignoring this metric
        n = {}
      else
        if not stats[tag_value] then
          stats[tag_value] = new_tab(0, expected_dp_count)
        end
        n = stats[tag_value]
      end
    end

    local status_code_tag = series.metric['status_code']
    if status_code_tag then
      local code
      if merge_status_class then
        code = sub(status_code_tag, 1, 1) .. "xx"
      else
        code = status_code_tag
      end

      local last_value, last_ts
      for _, dp in ipairs(series.values) do
        local incr_value
        -- if we use integer as key, cjson will complain excessively sparse array
        local k = fmt("%d", dp[1])
        -- 'NaN' will be parsed to math.nan and cjson will not encode it
        local v = tonumber(dp[2])
        -- See http://lua-users.org/wiki/InfAndNanComparisons
        if v ~= v then
          v = nil
        end
        if v ~= null and v ~= 0 then
          if not n[k] then
              n[k] = {}
          end
          -- if there's missed scrape, skip the current for calculating rate
          -- because we have zero knowledge with the previous counter value
          if last_ts and dp[1] - last_ts > interval then
            last_value = nil
          end
          -- only it's not the first data point at beginning or missed scrape
          if last_value ~= nil then
            -- add the data point
            if last_value > v then -- detect counter reset
              incr_value = v
            else
              incr_value = v - last_value
            end

            if merge_status_class then
              n[k][code] = incr_value + (n[k][code] or 0)
            else
              n[k][code] = incr_value
            end
          end
        end
        last_value = v
        last_ts = dp[1]

      end -- for _, dp in ipairs(series.values) do
    end -- do

  end -- for idx, series in ipairs(prometheus_stats[1]) do

  return ret, nil
end

local function get_interval_and_start_ts(level, start_ts, scrape_interval)
  local interval
  if tonumber(level) then
    interval = level
    if start_ts == nil then
      start_ts = ngx_time() - 720 * 60
    end
  elseif vitals_utils.interval_to_duration[level] then
    interval = vitals_utils.interval_to_duration[level]
    -- backward compatibility for client that doesn't send start_ts
    if start_ts == nil then
      start_ts = ngx_time() - 720 * 60
    end
  else
    interval = scrape_interval
    -- backward compatibility for client that doesn't send start_ts
    if start_ts == nil then
      start_ts = ngx_time() - 5 * 60
    end
  end

  return interval, start_ts
end


function _M:select_stats(query_type, level, node_id, start_ts, end_ts)
  local interval, start_ts = get_interval_and_start_ts(query_type, start_ts, self.scrape_interval)

  local metrics = self.common_stats_metrics

  local res, err, duration_seconds = self:query(
    start_ts,
    metrics,
    interval
  )

  if res then
    return translate_vitals_stats(metrics, res, interval, duration_seconds,
      self.cluster_level -- Cloud: set to true to hide node-level metrics
    )
  else
    return res, err
  end
end

function _M:select_status_codes(opts)
  local interval, start_ts = get_interval_and_start_ts(opts.duration, opts.start_ts, self.scrape_interval)

  -- build the filter table
  local filters = { }
  local filters_count = 0
  if self.has_custom_filters then
    filters_count = filters_count + 1
    filters[1] = self.custom_filters_str
  end

  local entity_type = opts.entity_type
  -- only merge status codes to like "2xx" when showing on /vitals/status-codes
  local merge_status_class = false
  if entity_type == "cluster" or entity_type == "workspace" then
    merge_status_class = true
  end

  local metric_name = "kong_status_code"
  local filter_fmt = "sum(%s{%s}) by (status_code)"

  if entity_type == "route" then
    metric_name = "kong_status_code_per_consumer"
    filters[filters_count + 1] = "route_id=\"" .. opts.entity_id .. "\""
    -- filter_fmt = "sum(%s{%s}) by (status_code)"
  elseif entity_type == "consumer_route" then
    metric_name = "kong_status_code_per_consumer"
    -- in statsd plugin we are regulating \. to _
    filters[filters_count + 1] = "consumer=\"" .. opts.entity_id .. "\""
    filters[filters_count + 2] = "route_id!=\"\"" -- route_id = "" will be per consumer per service events
    filter_fmt = "sum(%s{%s}) by (status_code, route_id)"
  elseif entity_type == "consumer" then
    metric_name = "kong_status_code_per_consumer"
    -- in statsd plugin we are regulating \. to _
    filters[filters_count + 1] = "consumer=\"" .. opts.entity_id .. "\""
    filters[filters_count + 2] = "route_id!=\"\"" -- route_id = "" will be per consumer per service events
    -- filter_fmt = "sum(%s{%s}) by (status_code)"
  elseif entity_type == "service" then
    -- don't merge kong_status_code_per_consumer with kong_status_code
    -- because there's not always consumer present

    -- use the default status_code metrics
    -- in statsd plugin we are regulating \. to _
    filters[filters_count + 1] = "service=\"" .. opts.entity_id .. "\""
  elseif entity_type == "workspace" then
    metric_name = "kong_status_code_per_workspace"
    filters[filters_count + 1] = "workspace=\"" .. opts.entity_id .. "\""
  end

  filters = table_concat(filters, ",")

  -- we only query one metric for select_status_codes
  local metric = { "status_code", fmt(filter_fmt, metric_name, filters), true }

  local res, err, duration_seconds = self:query(
    start_ts,
    { metric },
    interval
  )

  if res then
    return translate_vitals_status({ metric }, res, interval, duration_seconds,
      true, -- aggregate: GUI will not ask for node-level metrics
      merge_status_class,
      opts.key_by
    )
  end

  return nil, err
end

function _M:select_consumer_stats(opts)
  local interval, start_ts = get_interval_and_start_ts(opts.duration, opts.start_ts, self.scrape_interval)

  local metrics = {
    { "requests_consumer_total", fmt("sum(kong_status_code_per_consumer{consumer=\"%s\", route_id!=\"\", %s})",
                opts.consumer_id, self.custom_filters_str),
      true },
  }

  local res, err, duration_seconds = self:query(
    start_ts,
    metrics,
    interval
  )

  if res then
    return translate_vitals_stats(metrics, res, interval, duration_seconds,
      true -- Cloud: set to true to hide node-level metrics
    )
  else
    return res, err
  end
end

local function status_code_query(entity_id, entity)
  local is_consumer = entity == "consumer"
  local is_timeseries_report = entity_id ~= nil
  if is_consumer then
    if is_timeseries_report then
      return "sum(kong_status_code_per_consumer{consumer='" .. entity_id .. "'}) by (status_code)"
    else
      return "sum(kong_status_code_per_consumer) by (consumer, status_code)"
    end
  else
    if is_timeseries_report then
      return "sum(kong_status_code{service='" .. entity_id .. "'}) by (status_code)"
    else
      return "sum(kong_status_code) by (service, status_code)"
    end
  end
end
_M.status_code_query = status_code_query

-- Can produce a timeseries report for a given entity, or a summary of a given type of entity
-- @param[type=string] entity: consumer or service
-- @param[type=nullable-string] entity_id: UUID or nil, signifies how each row is indexed
-- @param[type=string] interval: seconds, minutes, hours, days, weeks, months
-- @param[type=number] start_ts: seconds from now
function _M:status_code_report_by(entity, entity_id, interval, start_ts)
  interval = interval or "minutes" -- query function requires an interval to get start_ts
  local duration = vitals_utils.interval_to_duration[interval]
  local entities = vitals_utils.get_entity_metadata(entity, entity_id)
  local metrics_query = status_code_query(entity_id, entity)
  local res, err = self:query(
    start_ts,
    {{"", metrics_query}},
    duration
  )

  if err then
    return err
  end

  local stats = {}
  local is_consumer = entity == "consumer"
  local is_timeseries_report = entity_id ~= nil

  for _, series_list in ipairs(res) do
    for _, series in ipairs(series_list) do
      local key, entity_metadata
      entity_metadata = entities[entity_id] or {}
      local status_group = tostring(series.metric.status_code):sub(1, 1) .. "XX"
      if is_timeseries_report then
        local last_value, last_ts
        for _, dp in ipairs(series.values) do
          local incr_value
          -- if we use integer as key, cjson will complain excessively sparse array
          local timestamp_number = dp[1]
          local timestamp = fmt("%d", dp[1])
          -- 'NaN' will be parsed to math.nan and cjson will not encode it
          local counter = tonumber(dp[2])
          -- See http://lua-users.org/wiki/InfAndNanComparisons
          local is_not_a_number = counter ~= counter
          if is_not_a_number then
            counter = nil
          end
          local counter_has_value = counter ~= null and counter ~= 0
          if counter_has_value then
            -- if there's missed scrape, skip the current for calculating rate
            -- because we have zero knowledge with the previous counter value
            if last_ts and timestamp_number - last_ts > duration then
              last_value = nil
            end
            -- only it's not the first data point at beginning or missed scrape
            if last_value ~= nil then
              -- add the data point
              if last_value > counter then -- detect counter reset
                incr_value = counter
              else
                incr_value = counter - last_value
              end

              stats = vitals_utils.append_to_stats(stats, timestamp, status_group, incr_value, entity_metadata)
            end
          end
          last_value = counter
          last_ts = timestamp_number
        end
      else
        key = series.metric[entity]
        local has_key = key ~= nil and key ~= ''
        if has_key then
          entity_metadata = entities[key] or {}
          local first_counter = tonumber(series.values[1][2])
          local last_counter = tonumber(series.values[#series.values][2])
          local request_count = last_counter - first_counter
          stats = vitals_utils.append_to_stats(stats, key, status_group, request_count, entity_metadata)
        end
      end
    end
  end
  local meta = {
    earliest_ts = start_ts,
    latest_ts = ngx.time(),
    stat_labels = {
      "name",
      "total",
      "2XX",
      "4XX",
      "5XX"
    },
  }
  if is_consumer then
    meta.stat_labels = {
      "name",
      "app_name",
      "app_id",
      "total",
      "2XX",
      "4XX",
      "5XX"
    }
  end
  return { stats=stats, meta=meta }
end

-- @param hostname: kong node hostname
-- @param interval: seconds, minutes, hours, days, weeks, months
-- @param start_ts: seconds from now
function _M:latency_report(hostname, interval, start_ts)
  -- TODO: implement
  return nil, "Not Implemented"
end


function _M:log()
  self.statsd_handler:log()
end



return _M
