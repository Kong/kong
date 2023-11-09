-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}


local cjson = require "cjson"
local ffi   = require "ffi"
local http  = require "resty.http"
local new_tab = require "table.new"
local clear_tab = require "table.clear"
local vitals_utils = require "kong.vitals.utils"


local ipairs        = ipairs
local math_floor    = math.floor
local math_max      = math.max
local ngx_time      = ngx.time
local string_format = string.format
local table_concat  = table.concat
local table_insert  = table.insert
local tonumber      = tonumber
local tostring      = tostring


local BUF_SIZE = 5000 -- number of points to buffer before flushing
local FLUSH_INTERVAL = 10 -- flush buffered points at most every 10
local MEASUREMENT = "kong_request" -- influx point measurement name


-- datastore cache format string
-- cheaper to format this string since we know the format
local CACHE_FMT = "kong_datastore_cache,hostname=%s,wid=%d hits=%di,misses=%di %s"

local function ffi_cdef_gettimeofday()
  ffi.cdef[[
      typedef long time_t;

      typedef struct timeval {
        time_t tv_sec;
        time_t tv_usec;
      } timeval;

      int gettimeofday(struct timeval* t, void* tzp);
  ]]
end

local ok = pcall(function() return ffi.C.gettimeofday end)
if not ok then
  ffi_cdef_gettimeofday()
end


local gettimeofday_struct = ffi.new("timeval")


local function gettimeofday()
    ffi.C.gettimeofday(gettimeofday_struct, nil)
    return string.format("%.f", tonumber(gettimeofday_struct.tv_sec) * 1000000 +
      tonumber(gettimeofday_struct.tv_usec))
end


local buf = new_tab(BUF_SIZE + 1, 0)
local buf_count = 0


-- reuse tables for :log()
local tags = new_tab(8, 0)
local fields = new_tab(4, 0)


local _log_prefix = "[vitals-influxdb] "


local mt = {
  __index = function(_, k, ...)
    local v = _M[k]
    if v ~= nil then
      return v
    end
    -- shouldn't go here, needs to add dummy functions in this module
    ngx.log(ngx.DEBUG, _log_prefix, string_format("function %s is not implemented for \"influxdb\" strategy\"", k))
    return function(...)
      return true, nil
    end
  end
}


local function get_flush_params(msg)
  local user = kong.configuration.vitals_tsdb_user
  local password = kong.configuration.vitals_tsdb_password
  local headers = _M.authorization_headers(user, password)

  return { headers = headers, method = "POST", body = msg }
end


local function flush(_, self, msg)
  local url = "http://" .. self.host .. ":" .. self.port .. "/write?db=kong&precision=u"
  local params = get_flush_params(msg)
  local httpc = http.new()

  local res, err = httpc:request_uri(url, params)

  if err then
    error(err)
  end

  if res.status ~= 204 then
    error(res.body)
  end

  -- socket is automatically put into keepalive for u
  -- thanks pintsized!
end


function _M.select_phone_home()
  return {}, nil
end


function _M.node_exists()
  return true, nil
end


function _M.new(db, opts)
  return setmetatable(opts, mt)
end


function _M:init(node_id, hostname)
  self.node_id  = node_id
  self.hostname = hostname
  self.wid      = ngx.worker.id()

  ngx.timer.every(FLUSH_INTERVAL, function()
    if buf_count > 0 then
      local m = table_concat(buf, "\n")
      clear_tab(buf)
      buf_count = 0

      flush(false, self, m)
    end
  end)

  return true, nil
end


-- no-op interface methods for handling runtime changes for vitals
function _M:start()
  return true
end
function _M:stop()
  return true
end


local function round(n)
  if not tonumber(n) then return n end

  if n + 0.5 >= math_floor(n + 1) then
    return math_floor(n + 1)
  else
    return math_floor(n)
  end
end


local stats_queries = {
  {
    "cache_datastore_hits_total",
    [[select sum(hits) from kong_datastore_cache]],
  },
  {
    "cache_datastore_misses_total",
    [[select sum(misses) from kong_datastore_cache]],
  },
  {
    "latency_proxy_request_min_ms",
    [[select min(kong_latency) from kong_request]],
  },
  {
    "latency_proxy_request_max_ms",
    [[select max(kong_latency) from kong_request]],
  },
  {
    "latency_upstream_min_ms",
    [[select min(proxy_latency) from kong_request]],
  },
  {
    "latency_upstream_max_ms",
    [[select max(proxy_latency) from kong_request]],
  },
  {
    "requests_proxy_total",
    [[select count(kong_latency) from kong_request]],
  },
  {
    "latency_proxy_request_avg_ms",
    [[select mean(kong_latency) from kong_request]],
  },
  {
    "latency_upstream_avg_ms",
    [[select mean(proxy_latency) from kong_request]],
  },
}


local function authorization_headers(user, password)
  if user ~= nil and password ~= nil then
    return { ["Authorization"] = "Basic " .. ngx.encode_base64(user .. ":" .. password)}
  end
  return {}
end
_M.authorization_headers = authorization_headers

local function prepend_protocol(address)
  if address:sub(1, #"http") ~= "http" then
    return "http://" .. address
  end
  return address
end
_M.prepend_protocol = prepend_protocol


local function query(self, q)
  local user = kong.configuration.vitals_tsdb_user
  local password = kong.configuration.vitals_tsdb_password
  local address = prepend_protocol(kong.configuration.vitals_tsdb_address)
  local httpc = http.new()

  local headers = authorization_headers(user, password)
  local url = address .. "/query?db=kong&epoch=s&q=" .. ngx.escape_uri(q)
  local res, err = httpc:request_uri(url, { headers = headers })
  if not res then
    error(err)
  end

  if res.status ~= 200 then
    error(res.body)
  end

  local qres = cjson.decode(res.body)

  if #qres.results == 1 and qres.results[1].series then
    return qres.results[1].series
  elseif #qres.results > 1 then
    return qres.results
  else
    return {}
  end

end


function _M:select_consumer_stats(opts)
  local int = opts.duration

  if not opts.start_ts then
    if opts.duration == 60 then
      opts.start_ts = ngx_time() - 720 * 60
    else
      opts.start_ts = ngx_time() - 5 * 60
    end
  end

  local meta = {
    earliest_ts = opts.start_ts,
    interval = vitals_utils.duration_to_interval[opts.duration],
    latest_ts = ngx_time(),
    level = opts.level,
    stat_labels = {
      "requests_consumer_total"
    },
  }

  local where_clause = " where consumer='" .. opts.consumer_id ..
    "' and time > now() - " .. ngx_time() - opts.start_ts .. "s"

  local group_by = " group by time(" .. int .. "s)"

  local q = "select count(status) from kong_request"

  local c = {}

  local res_t = query(self, q .. where_clause .. group_by)
  local res = res_t[1]

  local found_latest_ts = 0

  for _, value in ipairs(res.values) do
    if value[2] ~= 0 then
      found_latest_ts = math_max(found_latest_ts, value[1])

      local k = tostring(value[1]) -- timestamp

      c[k] = value[2]
    end
  end

  if found_latest_ts > 0 then
    meta.latest_ts = found_latest_ts
  end

  return {
    meta  = meta,
    stats = { cluster = c },
  }
end


function _M:select_status_codes(opts)
  local int = opts.duration

  local entity_type = opts.entity_type

  if not opts.start_ts then
    if opts.duration == 60 then
      opts.start_ts = ngx_time() - 720 * 60
    else
      opts.start_ts = ngx_time() - 5 * 60
    end
  end

  local meta = {
    earliest_ts = opts.start_ts,
    entity_type = opts.entity_type,
    interval = vitals_utils.duration_to_interval[opts.duration],
    latest_ts = ngx_time(),
    level = "cluster",
    workspace_id = ngx.ctx.workspace,
    stat_labels = {},
  }

  local found_latest_ts = 0

  local stats = {}
  local c = {}

  local q = "select count(status) from kong_request"

  local group_by = " group by time(" .. int .. "s),status_f"

  local where_clause = " where time > now() - " .. ngx_time() - opts.start_ts ..
    "s"

  if entity_type == "cluster" then
    table_insert(meta.stat_labels, "status_code_classes_total")

    local res_t = query(self, q .. where_clause .. group_by)

    for _, res in ipairs(res_t) do
      local status_x = string.sub(res.tags.status_f, 1, 1) .. "xx"

      for _, value in ipairs(res.values) do
        if value[2] > 0 then
          found_latest_ts = math_max(found_latest_ts, value[1])

          local k = tostring(value[1])

          if not c[k] then
            c[k] = {}
          end

          c[k][status_x] = value[2] + (c[k][status_x] or 0)
        end
      end
    end

    stats = { cluster = c }

  elseif entity_type == "workspace" then
    table_insert(meta.stat_labels, "status_code_classes_per_workspace_total")

    where_clause = where_clause .. " and workspace='" .. opts.entity_id ..
                   "'"

    local res_t = query(self, q .. where_clause .. group_by)

    for _, res in ipairs(res_t) do
      local status_x = string.sub(res.tags.status_f, 1, 1) .. "xx"

      for _, value in ipairs(res.values) do
        if value[2] > 0 then
          found_latest_ts = math_max(found_latest_ts, value[1])

          local k = tostring(value[1])

          if not c[k] then
            c[k] = {}
          end

          c[k][status_x] = value[2] + (c[k][status_x] or 0)
        end
      end
    end

    stats = { cluster = c }

  elseif entity_type == "service" or
         entity_type == "route" or
         entity_type == "consumer" then
    table_insert(meta.stat_labels, "status_codes_per_" .. entity_type .. "_total")

    where_clause = where_clause .. " and " .. entity_type .. "='" ..
                   opts.entity_id .. "'"

    local res_t = query(self, q .. where_clause .. group_by)

    for _, res in ipairs(res_t) do
      local status = tostring(res.tags.status_f)

      for _, value in ipairs(res.values) do
        if value[2] > 0 then
          found_latest_ts = math_max(found_latest_ts, value[1])

          local k = tostring(value[1])

          if not c[k] then
            c[k] = {}
          end

          c[k][status] = value[2]
        end
      end
    end
    stats = { cluster = c }

  elseif entity_type == "consumer_route" then
    table_insert(meta.stat_labels, "status_codes_per_consumer_route_total")

    where_clause = where_clause .. " and consumer='" .. opts.entity_id .. "'"

    group_by = group_by .. ",route"

    local res_t = query(self, q .. where_clause .. group_by)

    for _, res in ipairs(res_t) do
      local status = tostring(res.tags.status_f)
      local route = res.tags.route

      for _, value in ipairs(res.values) do
        if value[2] > 0 then
          if not c[route] then
            c[route] = {}
          end

          found_latest_ts = math_max(found_latest_ts, value[1])

          local k = tostring(value[1])

          if not c[route][k] then
            c[route][k] = {}
          end

          c[route][k][status] = value[2]
        end
      end
    end
    stats = c
  end

  if found_latest_ts > 0 then
    meta.latest_ts = found_latest_ts
  end

  return {
    meta  = meta,
    stats = stats,
  }
end

function _M:select_stats(query_type, level, node_id, start_ts, end_ts)
  -- group by time($int)
  local int = vitals_utils.interval_to_duration[query_type]

  if not start_ts then
    if query_type == "minutes" then
      start_ts = ngx_time() - 720 * 60
    else
      start_ts = ngx_time() - 5 * 60
    end
  end

  local meta = {
    earliest_ts = start_ts,
    interval = query_type,
    interval_width = vitals_utils.duration_to_interval[query_type],
    latest_ts = ngx_time(),
    level = level,
    workspace_id = ngx.ctx.workspace,
    stat_labels = {
      "cache_datastore_hits_total",
      "cache_datastore_misses_total",
      "latency_proxy_request_min_ms",
      "latency_proxy_request_max_ms",
      "latency_upstream_min_ms",
      "latency_upstream_max_ms",
      "requests_proxy_total",
      "latency_proxy_request_avg_ms",
      "latency_upstream_avg_ms",
    }
  }

  local where_clause = " where time > now() - " .. ngx_time() - start_ts .. "s"

  local stats = {}

  local found_latest_ts = 0

  local group_by = " group by time(" .. int .. "s)"

  if level == "cluster" then
    local c = {}

    local q_tab = {}
    for i, q in ipairs(stats_queries) do
      table_insert(q_tab, q[2] .. where_clause .. group_by)
    end

    local res_obj = query(self, table_concat(q_tab, ";"))

    for i, res in ipairs(res_obj) do
      local res_t = res.series

      if res_t then
        local res = res_t[1]
        for _, value in ipairs(res.values) do
          found_latest_ts = math_max(found_latest_ts, value[1])

          local k = tostring(value[1]) -- timestamp

          if not c[k] then
            c[k] = {}
          end

          c[k][i] = value[2] and round(value[2]) or cjson.null
        end
      end
    end

    stats.cluster = c

  else -- node
    local nodes = {}

    meta.nodes = {}

    group_by = group_by .. ",hostname"

    if node_id then
      where_clause = where_clause .. " and hostname='" .. node_id .. "'"
    end

    local q_tab = {}
    for i, q in ipairs(stats_queries) do
      table_insert(q_tab, q[2] .. where_clause .. group_by)
    end

    local res_obj = query(self, table_concat(q_tab, ";"))

    for i, res in ipairs(res_obj) do
      local res_t = res.series

      if res_t then
        for _, s in ipairs(res_t) do
          local hostname = s.tags.hostname

          if not meta.nodes[hostname] then
            meta.nodes[hostname] = { hostname = hostname } -- haaack
          end

          if not nodes[hostname] then
            nodes[hostname] = {}
          end

          for _, value in ipairs(s.values) do
            found_latest_ts = math_max(found_latest_ts, value[1])

            local k = tostring(value[1])

            if not nodes[hostname][k] then
              nodes[hostname][k] = {}
            end

            nodes[hostname][k][i] = value[2] and round(value[2]) or cjson.null
          end
        end
      end
    end

    stats = nodes
  end

  if found_latest_ts > 0 then
    meta.latest_ts = found_latest_ts
  end

  return {
    meta  = meta,
    stats = stats,
  }
end


local function status_code_query(entity_id, entity, seconds_from_now, interval)
  local q = "SELECT count(status) FROM kong_request"
  local where_clause = " WHERE time > now() - " .. seconds_from_now .. "s"
  local group_by = " GROUP BY status_f, "
  if entity_id == nil then
    group_by = group_by .. entity
  else
    where_clause = where_clause .. " and " .. entity .. "='" .. entity_id .."'"
    group_by = group_by .. " time(" .. vitals_utils.interval_to_duration[interval] .. "s)"
  end
  return q .. where_clause .. group_by
end
_M.status_code_query = status_code_query

-- Can produce a timeseries report for a given entity, or a summary of a given type of entity
-- @param[type=string] entity: consumer or service
-- @param[type=nullable-string] entity_id: UUID or nil, signifies how each row is indexed
-- @param[type=string] interval: seconds, minutes, hours, days, weeks, months
-- @param[type=number] start_ts: seconds from now
function _M:status_code_report_by(entity, entity_id, interval, start_ts)
  local entities = vitals_utils.get_entity_metadata(entity, entity_id)
  local seconds_from_now = ngx.time() - start_ts
  local result = query(self, status_code_query(entity_id, entity, seconds_from_now, interval))

  local stats = {}
  local is_consumer = entity == "consumer"
  local is_timeseries_report = entity_id ~= nil

  for _, series in ipairs(result) do
    for _, value in ipairs(series.values) do
      local key -- can either be a timestamp or an uuid
      local entity_metadata -- can either be an empty table or contain metadata fetched from kong db
      if is_timeseries_report then
        local timestamp = tostring(value[1])
        key = timestamp
        entity_metadata = entities[entity_id] or {}
      else
        local entity_tag = {
          consumer = series.tags.consumer,
          service = series.tags.service
        }
        key = entity_tag[entity]
        entity_metadata = entities[key] or {}
      end
      local has_key = key ~= nil and key ~= ''
      if has_key then
        local status_group = tostring(series.tags.status_f):sub(1, 1) .. "XX"
        local request_count = value[2]
        stats = vitals_utils.append_to_stats(stats, key, status_group, request_count, entity_metadata)
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


local function latency_query(hostname, seconds_from_now, interval)
  local q = "SELECT MAX(proxy_latency), MIN(proxy_latency)," ..
    " MEAN(proxy_latency), MAX(request_latency), MIN(request_latency)," ..
    " MEAN(request_latency) FROM kong_request"
  local where_clause = " WHERE time > now() - " .. seconds_from_now .. "s"
  local group_by = " GROUP BY "

  if hostname == nil then
    group_by = group_by .. "hostname"
  else
    where_clause = where_clause .. " AND hostname='" .. hostname .."'"
    group_by = group_by .. "time(" .. vitals_utils.interval_to_duration[interval] .. "s)"
  end
  return q .. where_clause .. group_by
end
_M.latency_query = latency_query


function _M:latency_report(hostname, interval, start_ts)
  local columns = {
    "proxy_max",
    "proxy_min",
    "proxy_avg",
    "upstream_max",
    "upstream_min",
    "upstream_avg",
  }

  local seconds_from_now = ngx.time() - start_ts
  local result = query(self, latency_query(hostname, seconds_from_now, interval))

  local stats = {}
  for _, series in ipairs(result) do
    for _, value in ipairs(series.values) do
      local key
      if hostname == nil then
        key = series.tags.hostname
      else
        key = tostring(value[1]) -- timestamp
      end
      stats[key] = stats[key] or {}

      for i, column in pairs(columns) do
        if value[i+1] ~= cjson.null then
          if string.match(column, "_avg") then
            stats[key][column] = math.floor(value[i+1])
          else
            stats[key][column] = value[i+1]
          end
        end
      end
    end
  end

  local meta = {
    earliest_ts = start_ts,
    latest_ts = ngx.time(),
    stat_labels = columns,
  }

  return { stats=stats, meta=meta }
end
function _M:log()
  clear_tab(tags)
  clear_tab(fields)

  tags[1] = MEASUREMENT -- cheat on the tab and put the measurement here

  local ctx = ngx.ctx

  local t = gettimeofday();

  if ctx.authenticated_consumer then
    table_insert(tags, "consumer=" .. ctx.authenticated_consumer.id)
  end
  table_insert(tags, "hostname=" .. self.hostname)
  if ctx.route then
    table_insert(tags, "route=" .. ctx.route.id)
  end
  if ctx.service then
    table_insert(tags, "service=" .. ctx.service.id)
  end
  table_insert(tags, "status_f=" .. ngx.status)
  table_insert(tags, "wid=" .. self.wid)
  table_insert(tags, "workspace=" .. ctx.workspace)

  local k = (ctx.KONG_ACCESS_TIME or 0) + (ctx.KONG_RECEIVE_TIME or 0) +
    (ctx.KONG_REWRITE_TIME or 0) + (ctx.KONG_BALANCER_TIME or 0)

  table_insert(fields, "kong_latency=" .. k .. "i")
  if ctx.KONG_WAITING_TIME then
    table_insert(fields, "proxy_latency=" .. ctx.KONG_WAITING_TIME .. "i")
  end
  table_insert(fields, "request_latency=" .. ngx.var.request_time * 1000 .. "i")
  table_insert(fields, "status=" .. ngx.status .. "i")

  local req_msg = string_format("%s %s %s", table_concat(tags, ","),
    table_concat(fields, ","), t)

  buf_count = buf_count + 1
  buf[buf_count] = req_msg

  if ctx.cache_metrics then
    local cache_msg = string_format(
      CACHE_FMT,
      self.hostname,
      self.wid,
      ctx.cache_metrics.cache_datastore_hits_total,
      ctx.cache_metrics.cache_datastore_misses_total,
      t
    )

    buf_count = buf_count + 1
    buf[buf_count] = cache_msg
  end

  if buf_count >= BUF_SIZE then
    local m = table_concat(buf, "\n")
    clear_tab(buf)
    buf_count = 0

    ngx.timer.at(0, flush, self, m)
  end
end

if _G._TEST then
  _M.get_flush_params = get_flush_params
  _M.gettimeofday = gettimeofday
end

return _M
