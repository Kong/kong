local _M = {}


local cjson = require "cjson"
local ffi   = require "ffi"
local http  = require "resty.http"


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


ffi.cdef[[
    typedef long time_t;

    typedef struct timeval {
        time_t tv_sec;
        time_t tv_usec;
    } timeval;

    int gettimeofday(struct timeval* t, void* tzp);
]]


local gettimeofday_struct = ffi.new("timeval")


local function gettimeofday()
    ffi.C.gettimeofday(gettimeofday_struct, nil)
    return tostring(tonumber(gettimeofday_struct.tv_sec)) ..
      tostring(tonumber(gettimeofday_struct.tv_usec))
end


local ok, new_tab = pcall(require, "table.new")
if not ok or type(new_tab) ~= "function" then
    new_tab = function (narr, nrec) return {} end
end


local ok, clear_tab = pcall(require, "table.clear")
if not ok then
  clear_tab = function(tab)
    for k in pairs(tab) do
      tab[k] = nil
    end
  end
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


local function flush(_, self, msg)
  local httpc = http.new()

  local res, err = httpc:request_uri("http://" .. self.host .. ":" ..
    self.port .. "/write?db=kong&precision=u",
    {
      method = "POST",
      body = msg,
    }
  )

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


local function query(self, q)
  local db = "kong"

  local httpc = http.new()

  local res, err = httpc:request_uri("http://" .. self.host .. ":" ..
    self.port .. "/query?db=" .. db .. "&epoch=s&q=" .. ngx.escape_uri(q)
  )
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
    interval = opts.duration == 60 and "minutes" or "seconds",
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
    interval = opts.duration == 60 and "minutes" or "seconds",
    latest_ts = ngx_time(),
    level = "cluster",
    workspace_id = ngx.ctx.workspaces[1].id,
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


function _M:select_stats(query_type, level, node_id, start_ts)
  -- group by time($int)
  local int = query_type == "minutes" and "1m" or "1s"

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
    interval_width = query_type == "minutes" and 60 or 1,
    latest_ts = ngx_time(), 
    level = level,
    workspace_id = ngx.ctx.workspaces[1].id,
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

  local group_by = " group by time(" .. int .. ")"

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
  table_insert(tags, "service=" .. ctx.service.id)
  table_insert(tags, "status_f=" .. ngx.status)
  table_insert(tags, "wid=" .. self.wid)
  table_insert(tags, "workspace=" .. ctx.workspaces[1].id)

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

return _M
