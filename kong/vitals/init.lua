local json_null  = require("cjson").null
local cjson      = require "cjson.safe"
local ffi        = require "ffi"
local tablex     = require "pl.tablex"
local pl_stringx = require "pl.stringx"
local reports    = require "kong.reports"
local utils      = require "kong.tools.utils"
local pg_strat   = require "kong.vitals.postgres.strategy"
local feature_flags = require "kong.enterprise_edition.feature_flags"


local timer_at   = ngx.timer.at
local time       = ngx.time
local sleep      = ngx.sleep
local floor      = math.floor
local math_min   = math.min
local math_max   = math.max
local log        = ngx.log
local DEBUG      = ngx.DEBUG
local INFO       = ngx.INFO
local WARN       = ngx.WARN
local ERR        = ngx.ERR
local FF_VALUES  = feature_flags.VALUES
local FF_FLAGS   = feature_flags.FLAGS

local fmt        = string.format
local kong = kong
local knode  = (kong and kong.node) and kong.node or
               require "kong.pdk.node".new()

local new_tab
do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function(narr, nrec)
      return {}
    end
  end
end


local STAT_LABELS = {
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


local CONSUMER_STAT_LABELS = {
  "requests_consumer_total",
}


local STATUS_CODE_STAT_LABELS = {
  cluster = {
    "status_code_classes_total",
  },
  workspace = {
    "status_code_classes_per_workspace_total",
  },
  service = {
    "status_codes_per_service_total",
  },
  route = {
    "status_codes_per_route_total",
  },
  consumer = {
    "status_codes_per_consumer_total",
  },
  consumer_route = {
    "status_codes_per_consumer_route_total",
  },
}


local persistence_handler
local _log_prefix = "[vitals] "


local FLUSH_LOCK_KEY = "vitals:flush_lock"
local FLUSH_LIST_KEY = "vitals:flush_list:"

local PH_STATS_KEY = "vitals:ph_stats"
local PH_STATS = {
  "v.cdht",
  "v.cdmt",
  "v.lprn",
  "v.lprx",
  "v.lun",
  "v.lux",
  "v.rpt",
  "v.nt",
  "v.lpra",
  "v.lua",
}

local worker_count = ngx.worker.count()


local _M = {}
local mt = { __index = _M }

-- map to where to find certain metrics in ngx.ctx, and what type they are
-- initially for use by logging plugins.
local logging_metrics = {
  cache_metrics = {
    cache_datastore_hits_total   = "counter",
    cache_datastore_misses_total = "counter",
  }
}
_M.logging_metrics = logging_metrics


--[[
  use signed ints to support sentinel values on "max" stats e.g.,
  proxy and upstream max latencies
]]
ffi.cdef[[
  typedef struct vitals_metrics_s {
    uint32_t    l2_hits;
    uint32_t    l2_misses;
    uint32_t    proxy_latency_min;
    int32_t     proxy_latency_max;
    uint32_t    ulat_min;
    int32_t     ulat_max;
    uint32_t    requests;
    uint32_t    proxy_latency_count;
    uint32_t    proxy_latency_total;
    uint32_t    ulat_count;
    uint32_t    ulat_total;
    uint32_t    timestamp;
  } vitals_metrics_t;
]]


local vitals_metrics_t_arr_type  = ffi.typeof("vitals_metrics_t[?]")
local vitals_metrics_t_size      = ffi.sizeof("vitals_metrics_t")
local const_vitals_metrics_t_ptr = ffi.typeof("const vitals_metrics_t*")


--[[
  returns an initialized array of vitals_metrics_t structs of size `sz`.
  when adding a new stat, include a reasonable default for it in the
  penultimate slot (the one before the timestamp). "Reasonable defaults" are
  * 0 - for counters
  * -1 - for stat max values (e.g., max proxy latency)
  * 0xFFFFFFFF - for stat min values

  Since min and max can be null (in the case where that metric wasn't logged
  in a particular interval), sentinel values are used. when we prepare to push
  stats to our strategy, we check for this sentinel value; if it exists,
  we never called the path to which the values are associated, meaning that
  these should be stored as nil.

  The final element is the timestamp associated with the bucket.
]]
local function metrics_t_arr_init(sz, start_at)
  local t = new_tab(sz, 0)

  for i = 1, sz do
    t[i] = { 0, 0, 0xFFFFFFFF, -1, 0xFFFFFFFF, -1, 0, 0, 0, 0, 0, start_at + i - 1 }
  end

  return t
end


local function load_tsdb_strategy(strategy)
  local conf = kong.configuration
  if strategy == "prometheus" then
    local db_strategy = require("kong.vitals.prometheus.strategy")

    local host, port
    host, port = conf.vitals_tsdb_address:match("(.+):([%d]+)$")
    port = tonumber(port)

    local tsdb_opts = {
      host = host,
      port = port,
      scrape_interval = conf.vitals_prometheus_scrape_interval,
      auth_header = feature_flags.get_feature_value(FF_VALUES.VITALS_PROMETHEUS_AUTH_HEADER),
      custom_filters = feature_flags.get_feature_value(FF_VALUES.VITALS_PROMETHEUS_CUSTOM_FILTERS),
      cluster_level = feature_flags.is_enabled(FF_FLAGS.VITALS_PROMETHEUS_ENABLE_CLUSTER_LEVEL),
    }
    -- no error and we are using TSDB strategy
    return db_strategy, tsdb_opts

  elseif strategy == "influxdb" then
    local db_strategy = require "kong.vitals.influxdb.strategy"

    local host, port
    host, port = conf.vitals_tsdb_address:match("(.+):([%d]+)$")
    port = tonumber(port)

    local tsdb_opts = {
      host = host,
      port = port,
    }

    return db_strategy, tsdb_opts
  else
    return error("no vitals TSDB strategy for " .. tostring(strategy))
  end
end


function _M.new(opts)
  opts = opts or {}

  if not opts.db then
    return error("opts.db is required")
  end

  if opts.flush_interval                   and
     type(opts.flush_interval) ~= "number" and
     opts.flush_interval % 1 ~= 0          then
    return error("opts.flush_interval must be an integer")
  end

  local strategy
  local tsdb_storage = false

  do
    local db = opts.db

    local strategy_opts = {
      ttl_seconds = opts.ttl_seconds or 3600,
      ttl_minutes = opts.ttl_minutes or 90000,
    }

    local db_strategy

    local vitals_strategy_conf = kong.configuration.vitals_strategy

    if not vitals_strategy_conf or vitals_strategy_conf == "database" then
      if db.strategy == "postgres" then
        db_strategy = pg_strat
        strategy_opts.delete_interval = opts.delete_interval_pg or 90000
      elseif db.strategy == "cassandra" then
        db_strategy = require "kong.vitals.cassandra.strategy"
      else
        return error("no vitals strategy for " .. db.strategy)
      end
    else
      -- use TSDB strategies
      db_strategy, strategy_opts = load_tsdb_strategy(vitals_strategy_conf)
      tsdb_storage = true
    end

    strategy = db_strategy.new(db, strategy_opts)
  end

  -- paradoxically, we set flush_interval to a very high default here,
  -- so that tests won't attempt to flush counters as a side effect.
  -- in a normal Kong scenario, opts.flush interval will be
  -- initialized from configuration.
  local self = {
    list_cache     = ngx.shared.kong_vitals_lists,
    counter_cache  = ngx.shared.kong_vitals_counters,
    strategy       = strategy,
    counters       = {},
    flush_interval = opts.flush_interval or 90000,
    ttl_seconds    = opts.ttl_seconds or 3600,
    ttl_minutes    = opts.ttl_minutes or 90000,
    initialized    = false,
    tsdb_storage   = tsdb_storage,
  }

  return setmetatable(self, mt)
end


function _M:enabled()
  return kong.configuration.vitals and self.initialized
end


function _M:init()
  if not kong.configuration.vitals then
    return self:init_failed("vitals not enabled")
  end

  log(DEBUG, _log_prefix, "init")

  -- get node id (uuid)
  local node_id, err = knode.get_id()

  if err then
    return self:init_failed(nil, err)
  end

  self.node_id = node_id

  local delay = self.flush_interval
  local when  = delay - (ngx.now() - (math.floor(ngx.now() / delay) * delay))
  log(INFO, _log_prefix, "starting vitals timer (1) in ", when, " seconds")

  local ok, err = timer_at(when, persistence_handler, self)
  if ok then
    self:reset_counters()
  else
    return self:init_failed(nil, "failed to start recurring vitals timer (1): " .. err)
  end

  -- init strategy, recording node id and hostname in db
  local ok, err = self.strategy:init(node_id, utils.get_hostname())
  if not ok then
    return self:init_failed(nil, "failed to init vitals strategy " .. err)
  end

  self.initialized = true

  -- we're configured, initialized, and ready to phone home
  reports.add_ping_value("vitals", true)
  for _, v in ipairs(PH_STATS) do
    reports.add_ping_value(v, function()
      local res, err = kong.vitals:phone_home(v)
      if err then
        log(WARN, _log_prefix, "failed to retrieve stats: ", err)
        return nil
      end

      return res
    end)
  end

  return "ok"
end


function _M:init_failed(msg, err)
  reports.add_ping_value("vitals", false)
  return msg, err
end


persistence_handler = function(premature, self)
  if premature then
    -- we could flush counters now
    return
  end

  if self.tsdb_storage then
    -- TSDB strategy is read-only, the metrics will be sent by statsd-advanced plugin.
    return
  end

  -- if we've drifted, get back in sync
  local delay = self.flush_interval
  local when  = delay - (ngx.now() - (math.floor(ngx.now() / delay) * delay))

  -- only adjust if we're off by 1 second or more, otherwise we spawn
  -- a gazillion timers and run out of memory.
  when = when < 1 and delay or when

  log(DEBUG, _log_prefix, "starting vitals timer (2) in " .. when .. " seconds")


  local ok, err = timer_at(when, persistence_handler, self)
  if not ok then
    return nil, "failed to start recurring vitals timer (2): " .. err
  end

  local _, err = self:flush_counters()
  if err then
    log(ERR, _log_prefix, "flush_counters() threw an error: ", err)
  end
end


local function parse_cache_key(key)
  local keys = {}

  for k in key:gmatch("([^|]*)|") do
    table.insert(keys, k)
  end

  return keys
end


local function average_value(total, count)
  if count > 0 then
    return math.floor((total / count) + 0.5)
  end
end


-- converts Kong stats to format expected by Vitals API
local function convert_stats(vitals, res, level, interval)
  if vitals.tsdb_storage then
    -- don't translate since we already translated in TSDB strategy
    return res
  end

  local stats = {}
  local meta = {
    level = level,
    interval = interval,
    interval_width = vitals.strategy:interval_width(interval),
  }

  -- no stats to process, return minimal metadata along with empty stats
  if not res[1] then
    return { stats = stats, meta = meta }
  end

  meta.earliest_ts = 0xFFFFFFFF
  meta.latest_ts = -1
  meta.stat_labels = STAT_LABELS

  local nodes = {}
  local nodes_idx = {}
  local next_idx = 1
  for _, row in ipairs(res) do
    -- keep track of the node ids in this time series
    if not nodes_idx[row.node_id] then
      nodes_idx[row.node_id] = next_idx
      nodes[next_idx] = row.node_id
      next_idx = next_idx + 1
    end

    meta.earliest_ts = math_min(meta.earliest_ts, tonumber(row.at))
    meta.latest_ts = math_max(meta.latest_ts, tonumber(row.at))

    stats[row.node_id] = stats[row.node_id] or {}

    stats[row.node_id][tostring(row.at)] = {
      row.l2_hit,
      row.l2_miss,
      row.plat_min or json_null,
      row.plat_max or json_null,
      row.ulat_min or json_null,
      row.ulat_max or json_null,
      row.requests,
      average_value(row.plat_total, row.plat_count) or json_null,
      average_value(row.ulat_total, row.ulat_count) or json_null,
    }
  end

  -- only include nodes in metadata if it's a node-level request
  if level == "node" then
    meta.nodes = vitals:get_node_meta(nodes)
  end

  return { stats = stats, meta = meta }
end


-- converts Kong status codes to format expected by Vitals API
local function convert_status_codes(res, meta, key_by)
  local stats = {}

  -- clean up the meta table
  meta.stat_labels =  STATUS_CODE_STAT_LABELS[meta.entity_type or "cluster"]
  meta.interval = meta.duration
  meta.duration = nil

  -- no stats to process, return minimal metadata along with empty stats
  if not res[1] then
    return { stats = stats, meta = meta }
  end

  meta.earliest_ts = 0xFFFFFFFF
  meta.latest_ts = -1

  for _, row in ipairs(res) do
    local key = key_by and row[key_by] or "cluster"
    local at = tostring(row.at)
    local code = row.code_class and row.code_class .. "xx" or tostring(row.code)

    meta.earliest_ts = math_min(meta.earliest_ts, at)
    meta.latest_ts = math_max(meta.latest_ts, at)

    stats[key] = stats[key] or {}
    stats[key][at] = stats[key][at] or {}
    stats[key][at][code] = row.count
  end

  return { stats = stats, meta = meta }
end


-- converts consumer stats to format expected by Vitals API
local function convert_consumer_stats(vitals, res, level, interval)
  if vitals.tsdb_storage then
    -- don't translate since we already translated in TSDB strategy
    return res
  end

  local stats = {}
  local meta = {
    level = level,
    interval = interval,
  }

  -- no stats to process, return minimal metadata along with empty stats
  if not res[1] then
    return { stats = stats, meta = meta }
  end

  meta.earliest_ts = 0xFFFFFFFF
  meta.latest_ts = -1
  meta.stat_labels = CONSUMER_STAT_LABELS

  local nodes = {}
  local nodes_idx = {}
  local next_idx = 1
  for _, row in ipairs(res) do
    -- keep track of the node ids in this time series
    if not nodes_idx[row.node_id] then
      nodes_idx[row.node_id] = next_idx
      nodes[next_idx] = row.node_id
      next_idx = next_idx + 1
    end

    meta.earliest_ts = math_min(meta.earliest_ts, tonumber(row.at))
    meta.latest_ts = math_max(meta.latest_ts, tonumber(row.at))

    stats[row.node_id] = stats[row.node_id] or {}
    stats[row.node_id][tostring(row.at)] = row.count
  end

  -- only include nodes in metadata if it's a node-level request
  if level == "node" then
    meta.nodes = vitals:get_node_meta(nodes)
  end

  return { stats = stats, meta = meta }
end


local function build_flush_key(vitals)
  return FLUSH_LIST_KEY
end


-- acquire a lock for flushing counters to the database
function _M:flush_lock()
  local ok, err = self.list_cache:safe_add(FLUSH_LOCK_KEY, true,
    self.flush_interval - 0.01)
  if not ok then
    if err ~= "exists" then
      log(ERR, _log_prefix, "failed to acquire lock: ", err)
    end

    return false
  end

  return true
end


function _M:poll_worker_data(flush_key, expected)
  local i = 0

  if not expected then
    expected = worker_count
  end

  while true do
    sleep(math_max(self.flush_interval / 100, 0.001))

    local num_posted, err = self.list_cache:llen(flush_key)
    if err then
      return nil, err
    end

    if num_posted == expected then
      break
    end

    -- wait for a bit for all workers to report, then write what we've got
    i = i + 1
    if i > 10 then
      log(INFO, _log_prefix, num_posted, " of ", expected, " workers reported.")
      break
    end
  end

  return true
end


function _M:merge_worker_data(flush_key)
  local flush_data = new_tab(self.flush_interval, 0)

  -- for each elt in our list, pop it off and convert it to a read-only
  -- vitals_metrics_t[] (technically a vitals_metrics_t*). from here we can
  -- transform it as the strategy expects
  --
  -- n.b. currently this is a nasty polynomial function. this could use
  -- improvement in the future
  for i = 1, self.list_cache:llen(flush_key) do
    local v, err = self.list_cache:rpop(flush_key)

    if not v then
      return nil, err
    end

    local vitals_metrics_t = ffi.cast(const_vitals_metrics_t_ptr, v)

    for i = 1, self.flush_interval do
      local c = vitals_metrics_t[i - 1]

      -- this is an expected condition, particularly the first time a worker
      -- flushes data
      if time() - c.timestamp < 1 then
        log(DEBUG, _log_prefix, "unexpected timestamp ", c.timestamp, " at ",
            time(), ". Did this node just start up? If so, this condition is harmless.")
        break
      end

      local f = flush_data[i]

      -- hits and misses are just a cumulative sum
      local l2_hits = f and f[2] + c.l2_hits or c.l2_hits
      local l2_misses = f and f[3] + c.l2_misses or c.l2_misses

      -- if this was previously defined, the result is the min of the previous
      -- definition and our value (since our value is a sentinel the resulting
      -- min is correct). otherwise, we check for the presence of our sentinel
      -- and assign accordingly (either a nil type, or the bucket value)
      local plat_min = f and f[4] and math_min(f[4], c.proxy_latency_min) or c.proxy_latency_min

      -- the same logic applies for max as did for min
      local plat_max = f and f[5] and math_max(f[5], c.proxy_latency_max) or c.proxy_latency_max

      -- upstream latency: same logic as for proxy latency
      local ulat_min = f and f[6] and math_min(f[6], c.ulat_min) or c.ulat_min
      local ulat_max = f and f[7] and math_max(f[7], c.ulat_max) or c.ulat_max

      -- total requests: cumulative sum
      local requests = f and f[8] + c.requests or c.requests

      -- Collect proxy latency count and total (used for proxy latency average)
      local plat_count = f and f[9] + c.proxy_latency_count or c.proxy_latency_count
      local plat_total = f and f[10] + c.proxy_latency_total or c.proxy_latency_total

      -- Collect upstream latency count and total (used for upstream latency average)
      local ulat_count = f and f[11] + c.ulat_count or c.ulat_count
      local ulat_total = f and f[12] + c.ulat_total or c.ulat_total

      flush_data[i] = {
        c.timestamp,
        l2_hits,
        l2_misses,
        plat_min,
        plat_max,
        ulat_min,
        ulat_max,
        requests,
        plat_count,
        plat_total,
        ulat_count,
        ulat_total,
      }

      -- set proxy latency min and max to nil if min is still the default
      if flush_data[i][4] == 0xFFFFFFFF then
        flush_data[i][4] = nil
        flush_data[i][5] = nil
      end

      -- set upstream latency min and max to nil if min is still the default
      if flush_data[i][6] == 0xFFFFFFFF then
        flush_data[i][6] = nil
        flush_data[i][7] = nil
      end
    end
  end

  return flush_data
end


--[[
  cache keys are of the form
    at|duration|service|route|code|...

  This table is a helper to extract identifiers by name instead of position
]]
local IDX = {
  at = 1,
  duration = 2,
  service = 3,
  route = 4,
  code = 5,
  consumer = 6,
  workspaces = 7,
}


local KEY_FORMATS = {
  codes_route = {
    key_format = "%s|%s|%s|%s|%s|",
    key_values = { IDX.route, IDX.service, IDX.code, IDX.at, IDX.duration },
    required_fields = { IDX.route, IDX.service },
  },
  codes_service = {
    key_format = "%s|%s|%s|%s|",
    key_values = { IDX.service, IDX.code, IDX.at, IDX.duration },
    required_fields = { IDX.service },
  },
  code_classes = {
    key_format = "%s|%s|%s|",
    key_values = { IDX.code, IDX.at, IDX.duration },
    required_fields = { IDX.code },
  },
  code_classes_workspace = {
    key_format = "%s|%s|%s|%s|",
    key_values = { IDX.workspaces, IDX.code, IDX.at, IDX.duration },
    required_fields = { IDX.workspaces, IDX.code },
  },
  requests_consumer= {
    key_format = "%s|%s|%s|",
    key_values = { IDX.consumer, IDX.at, IDX.duration },
    required_fields = { IDX.consumer },
  },
  codes_consumer_route = {
    key_format = "%s|%s|%s|%s|%s|%s|",
    key_values = { IDX.consumer, IDX.route, IDX.service, IDX.code, IDX.at, IDX.duration },
    required_fields = { IDX.consumer, IDX.route, IDX.service },
  },
}


local function extract_keys(master_keys, requested_indexes)
  local new_key_parts = {}

  for _, v in ipairs(requested_indexes) do
    table.insert(new_key_parts, master_keys[v])
  end

  return new_key_parts
end

--[[
 turn
 {
    ["c903518b-ed9a-475d-8918-50ab886e2ffc|200|1522861680|60|"] = 3,
    ["c903518b-ed9a-475d-8918-50ab886e2ffc|200|1522861717|1|"] = 1,
    ["c903518b-ed9a-475d-8918-50ab886e2ffc|404|1522861680|60|"] = 4,
  }
  into
  {
    { "c903518b-ed9a-475d-8918-50ab886e2ffc", "200", "1522861680", "60", 3 },
    { "c903518b-ed9a-475d-8918-50ab886e2ffc", "200", "1522861717", "1", 1 }
    { "c903518b-ed9a-475d-8918-50ab886e2ffc", "404", "1522861680", "60", 4 },
  }
 ]]
local function flatten_counters(counters)
  local flattened_counters = {}

  local i = 1
  local row
  local count_idx

  for k, count in tablex.sort(counters) do
    row = parse_cache_key(k)
    count_idx = count_idx or #row + 1
    row[count_idx] = count
    flattened_counters[i] = row
    i = i + 1
  end

  return flattened_counters
end


--[[
  "prep*" functions prepare the data we'll pass to the db strategy from
  the cache entry we're processing.
 ]]
local function prep_counters(query_type, keys, count, data)
  if query_type == nil then
    return nil, "query_type is required"
  end

  -- are we counting by service, or route, or ... ?
  local count_by = KEY_FORMATS[query_type]

  if not count_by then
    return nil, "unknown query_type: " .. query_type
  end

  -- do we have the keys we need for this counter?
  for _, field in ipairs(count_by.required_fields) do
    if keys[field] == "" then
      return
    end
  end

  local row = fmt(count_by.key_format, unpack(extract_keys(keys, count_by.key_values)))

  if data[row] then
    data[row] = data[row] + count
  else
    data[row] = count
  end
end


local function prep_code_class_counters(query_type, keys, count, data)
  local code = keys[IDX.code]

  if tonumber(code) then
    -- this one requires a little transformation: though we logged 404, for
    -- example, we want to store 4.
    local new_keys = utils.shallow_copy(keys)

    new_keys[IDX.code] = floor(code / 100)

    -- create rows for each workspace
    local workspaces = pl_stringx.split(keys[IDX.workspaces], ",")
    for _, ws in ipairs(workspaces) do
      new_keys[IDX.workspaces] = ws
      prep_counters(query_type, new_keys, count, data)
    end
  end
end


function _M:flush_vitals_cache(batch_size, max)
  log(DEBUG, _log_prefix, "flushing vitals cache")

  if not batch_size or type(batch_size) ~= "number" then
    batch_size = 1024
  end

  -- keys are continually added to cache, so we'll never be "done",
  -- and we don't want to tie up this worker indefinitely. So,
  -- process at most 10% of our cache capacity. When it's available,
  -- we might use ngx.dict:free_space() to judge how full our cache
  -- is and how much we should work off.
  if not max or type(max) ~= "number" then
    max = 40960  -- TODO change this once we decide size of kong_vitals dict
  end

  local keys = self.counter_cache:get_keys(batch_size)
  local num_fetched = #keys

  -- how many keys have we processed?
  local num_processed = 0

  while num_fetched > 0 and num_processed < max do
    -- TODO now we can't preallocate data tables, because this cache is
    -- generic and not guaranteed that every entry will have a consumer, or a
    -- service, etc.
    local codes_per_service = {}
    local codes_per_route = {}
    local codes_per_consumer_route = {}
    local code_classes = {}
    local code_classes_per_workspace = {}
    local requests_per_consumer = {}

    for i, key in ipairs(keys) do
      local count, err = self.counter_cache:get(key)

      if count then
        self.counter_cache:delete(key) -- trust that the inserts will succeed

        local key_parts = parse_cache_key(key)

        prep_counters("codes_service", key_parts, count, codes_per_service)
        prep_counters("codes_route", key_parts, count, codes_per_route)
        prep_counters("codes_consumer_route", key_parts, count, codes_per_consumer_route)
        prep_code_class_counters("code_classes", key_parts, count, code_classes)
        prep_code_class_counters("code_classes_workspace", key_parts, count, code_classes_per_workspace)
        prep_counters("requests_consumer", key_parts, count, requests_per_consumer)

      elseif err then
        log(WARN, _log_prefix, "failed to fetch ", key, ". err: ", err)

      else
        log(DEBUG, _log_prefix, key, " not found")
      end
    end

    -- call the appropriate strategy function for each dataset
    local datasets = {
      insert_status_codes_by_service = flatten_counters(codes_per_service),
      insert_status_codes_by_route = flatten_counters(codes_per_route),
      insert_status_codes_by_consumer_and_route = flatten_counters(codes_per_consumer_route),
      insert_status_code_classes = flatten_counters(code_classes),
      insert_status_code_classes_by_workspace = flatten_counters(code_classes_per_workspace),
      insert_consumer_stats = flatten_counters(requests_per_consumer),
    }

    for fn, data in pairs(datasets) do
      local ok, err = self.strategy[fn](self.strategy, data)
      if not ok then
        log(WARN, _log_prefix, fn, " failed: ", err)
      end
    end

    num_processed = num_processed + num_fetched

    keys = self.counter_cache:get_keys(batch_size)
    num_fetched = #keys
  end

  log(DEBUG, _log_prefix, "total keys processed: ", num_processed)
  return num_processed
end


function _M:flush_counters()
  -- acquire the lock at the beginning of our lock routine. we may not have the
  -- lock here, but we are still going to push up our data
  local lock = self:flush_lock()
  local flush_key

  -- create a new string object that we can push to our shared list
  do
    local buf = ffi.string(self.counters.metrics,
                           vitals_metrics_t_size * self.flush_interval)

    flush_key = build_flush_key(self)

    log(DEBUG, _log_prefix, "pid ", ngx.worker.pid(), " caching metrics for ",
        self.counters.start_at)

    local ok, err = self.list_cache:rpush(flush_key, buf)
    if not ok then
      -- this is likely an OOM error, dont want to stop processing here
      log(ERR, _log_prefix, "error attempting to push to list: ", err)
    end
  end

  -- reset counters table. this applies to all workers
  self:reset_counters()

  -- if we're in charge of pushing to the strategy, lets hang tight for a bit
  -- and wait for each worker to push up their data. we will then coalesce it
  -- into the data form that vitals strategies expect
  if lock then
    log(DEBUG, _log_prefix, "pid ", ngx.worker.pid(), " acquired lock")
    local ok, err = self:poll_worker_data(flush_key)
    if not ok then
      -- timeout while polling data
      return nil, err
    end

    log(DEBUG, _log_prefix, "merge worker data")
    local flush_data, err = self:merge_worker_data(flush_key)
    if not flush_data then
      return nil, err
    end

    -- we're done? :shipit:
    log(DEBUG, _log_prefix, "execute strategy insert")
    local ok, err = self.strategy:insert_stats(flush_data)
    if not ok then
      return nil, err
    end

    -- clean up expired stats data
    log(DEBUG, _log_prefix, "delete expired stats")
    local expiries = {
      minutes = self.ttl_minutes,
    }
    local ok, err = self.strategy:delete_stats(expiries)
    if not ok then
      log(WARN, _log_prefix, "failed to delete stats: ", err)
    end

    -- now flush additional entity counters
    self:flush_vitals_cache()
  end

  log(DEBUG, _log_prefix, "flush done")

  return true
end


local function increment_counter(vitals, counter_name)
  -- increment in our bucket
  local bucket, err = vitals:current_bucket()

  if bucket then
    vitals.counters.metrics[bucket][counter_name] = vitals.counters.metrics[bucket][counter_name] + 1
  else
    log(DEBUG, _log_prefix, err)
  end

  -- increment in ngx.ctx
  local cache_metrics = ngx.ctx.cache_metrics or {
    cache_datastore_hits_total = 0,
    cache_datastore_misses_total = 0,
  }

  -- assume it's a hit
  local ctx_key = "cache_datastore_hits_total"
  if counter_name == "l2_misses" then
    ctx_key = "cache_datastore_misses_total"
  end

  cache_metrics[ctx_key] = cache_metrics[ctx_key] + 1

  -- make sure it's set -- we may have init'ed cache_metrics in this call
  ngx.ctx.cache_metrics = cache_metrics
end


function _M:reset_counters(counters)
  local counters = counters or self.counters

  counters.start_at = time()
  counters.metrics  = ffi.new(vitals_metrics_t_arr_type, self.flush_interval,
                        metrics_t_arr_init(self.flush_interval, counters.start_at))

  return counters
end


function _M:current_bucket()
  if self.tsdb_storage then
    -- returns nil to disable aggreation and writing
    -- because in this case we are send metrics via a statsd-advanced plugin and not Vitals.
    return nil
  end

  local bucket = time() - self.counters.start_at

  -- we may be collecting data points into the flush_interval+1 second.
  -- Put it in our last bucket on the grounds that it's better to report
  -- it in the wrong second than not at all.
  if bucket > self.flush_interval - 1 then
    bucket = self.flush_interval - 1
  end

  if bucket < 0 or bucket > self.flush_interval - 1 then
    return nil, "bucket " .. bucket ..
        " out of range for counters starting at " .. self.counters.start_at
  end

  return bucket
end



-- converts node metadata into a table to be included in stats responses
function _M:get_node_meta(node_ids)
  local nodes, err = self.strategy:select_node_meta(node_ids)

  if err then
    return nil, "failed to select node metadata: " .. err
  end

  local node_meta = {}
  for i, v in ipairs(nodes) do
    node_meta[v.node_id] = { hostname = v.hostname }
  end

  return node_meta
end



function _M:phone_home(stat_label)
  local res, err = self.list_cache:get(PH_STATS_KEY)

  if err then
    log(WARN, _log_prefix, "error retrieving phone home stats: ", err, ". Retrying...")
  end

  if res then
    res, err = cjson.decode(res)
    if not res then
      log(WARN, _log_prefix, "failed to decode phone home stats: ", err)
      res = {{}}
    end

  else
    -- not in cache, look in db
    res, err = self.strategy:select_phone_home()
    if not res then
      return nil, err
    end

    -- no stats is odd, but not an error
    if not res[1] then
      res[1] = {}
    end

    -- cache results briefly so that all stats for a report are fetched at once
    local _, c_err = self.list_cache:add(PH_STATS_KEY, cjson.encode(res), 10)

    if c_err then
      log(WARN, _log_prefix, "failed to cache phone home: ", c_err)
    end
  end

  return res[1][stat_label]
end


--[[
                         FOR THE VITALS API
  Functions in this section are called by the Vitals (Admin) API.
 ]]
function _M:get_index()

  local data = {
    stats = {}
  }

  local intervals_data = {
    seconds = {
      retention_period_seconds = self.ttl_seconds,
    },
    minutes = {
      retention_period_seconds = self.ttl_minutes,
    },
  }

  local levels_data = {
    cluster = {
      intervals = intervals_data,
    },
    nodes = {
      intervals = intervals_data,
    },
  }

  for _, stat in ipairs(STAT_LABELS) do
    data.stats[stat] = {
      levels = levels_data,
    }
  end

  for _, stat in ipairs(CONSUMER_STAT_LABELS) do
    data.stats[stat] = {
      levels = levels_data,
    }
  end

  for _, stats in pairs(STATUS_CODE_STAT_LABELS) do
    for _, stat in ipairs(stats) do
      data.stats[stat] = {
        levels = {
          cluster = levels_data.cluster
        },
      }
    end
  end

  return data
end


function _M:get_stats(query_type, level, node_id, start_ts)
  if query_type ~= "minutes" and query_type ~= "seconds" then
    return nil, "Invalid query params: interval must be 'minutes' or 'seconds'"
  end

  if level ~= "cluster" and level ~= "node" then
    return nil, "Invalid query params: level must be 'cluster' or 'node'"
  end

  if not utils.is_valid_uuid(node_id) and node_id ~= nil then
    return nil, "Invalid query params: invalid node_id"
  end

  if start_ts and not tonumber(start_ts) then
    return nil, "Invalid query params: start_ts must be a number"
  end

  local res, err = self.strategy:select_stats(query_type, level, node_id, start_ts)

  if res and not res[1] then
    local node_exists, node_err = self.strategy:node_exists(node_id)

    if node_err then
      log(WARN, _log_prefix, node_err)
      return {}
    end

    if not node_exists then
      return nil, "node does not exist"
    end
  end

  if err then
    log(WARN, _log_prefix, err)
    return {}
  end

  return convert_stats(self, res, level, query_type)
end

function _M:get_status_codes(opts, key_by)
  if opts.duration ~= "minutes" and opts.duration ~= "seconds" then
    return nil, "Invalid query params: interval must be 'minutes' or 'seconds'"
  end

  -- we don't collect status codes or status code classes at the node level
  if opts.level ~= "cluster" then
    return nil, "Invalid query params: level must be 'cluster'"
  end

  if opts.start_ts and not tonumber(opts.start_ts) then
    return nil, "Invalid query params: start_ts must be a number"
  end

  -- TODO ensure the requested entity is in the requested workspace (if any)
  -- currently depending on the API (api/init.lua) to do that check

  local query_opts = {
    duration = opts.duration == "seconds" and 1 or 60,
    start_ts = opts.start_ts,
    entity_type = opts.entity_type,
    entity_id = opts.entity_id,
    key_by = key_by,
  }

  local res, err = self.strategy:select_status_codes(query_opts)

  if err then
    log(WARN, _log_prefix, err)
    return {}
  elseif self.tsdb_storage then
    -- don't translate since we already translated in TSDB strategy
    -- don't move this into convert_status_codes and use kong.vitals since it may not be set
    return res
  end

  return convert_status_codes(res, opts, key_by)
end

--[[
For use by the Vitals API to retrieve consumer stats
(currently total request count per consumer).
opts includes the following:
  consumer_id = <consumer uuid>,
  duration    = <"seconds" or "minutes">,
  level       = <"node" or "cluster">,
  node_id     = <node uuid (optional)>

return value is a table:
{
  meta = {
    consumer = {
      id = <uuid>,
    },
    node = {
      id       = <uuid>,
    }, -- an empty table if node_id wasn't provided in opts
    interval = "seconds",
  },
  stats = {
    <node_id> = { <- node_id is a node uuid or "cluster"
      ts = count,
      ts = count,
      ...
    },
  }
}

]]
function _M:get_consumer_stats(opts)
  if not opts.consumer_id or not opts.duration or not opts.level then
    return nil, "Invalid query params: consumer_id, duration, and level are required"
  end

  if opts.duration ~= "seconds" and opts.duration ~= "minutes" then
    return nil, "Invalid query params: interval must be 'minutes' or 'seconds'"
  end

  if opts.level ~= "node" and opts.level ~= "cluster" then
    return nil, "Invalid query params: level must be 'node' or 'cluster'"
  end

  if opts.node_id and not utils.is_valid_uuid(opts.node_id) then
    return nil, "Invalid query params: invalid node_id"
  end

  if opts.start_ts and not tonumber(opts.start_ts) then
    return nil, "Invalid query params: start_ts must be a number"
  end

  local query_opts = {
    consumer_id = opts.consumer_id,
    duration    = opts.duration == "seconds" and 1 or 60,
    level       = opts.level,
    node_id     = opts.node_id,
    start_ts    = opts.start_ts,
  }

  local res, _ = self.strategy:select_consumer_stats(query_opts)

  if not res then
    return nil, "Failed to retrieve stats for consumer " .. opts.consumer_id
  end

  return convert_consumer_stats(self, res, opts.level, opts.duration)
end


--[[
                         INTERFACES TO KONG CORE
  Functions in this section are called by Kong core when Vitals is enabled.
  In general, no errors should percolate up from these functions -- trap and
  log here so that core does not have to do any exception handling for Vitals.
 ]]

--[[
  Returns the names of tables created by the vitals module, mainly for use in
  `kong migrations reset`. Add to this list when you create a new vitals table.
 ]]
function _M.table_names(db)

  -- tables common across both dbs
  local table_names = {
    "vitals_code_classes_by_cluster",
    "vitals_code_classes_by_workspace",
    "vitals_codes_by_consumer_route",
    "vitals_codes_by_route",
    "vitals_codes_by_service",
    "vitals_consumers",
    "vitals_locks",
    "vitals_node_meta",
    "vitals_stats_hours",
    "vitals_stats_minutes",
    "vitals_stats_seconds",
  }
  local table_count = #table_names

  if db.strategy == "postgres" then
    -- pick up the tables created at runtime
    for i, v in ipairs(pg_strat.dynamic_table_names(db)) do
      table_names[table_count+i] = v
    end
  end

  return table_names
end


function _M:cache_accessed(hit_lvl, key, value)
  if not self:enabled() then
    return "vitals not enabled"
  end

  local counter_name

  if hit_lvl == 2 then
    counter_name = "l2_hits"
  elseif hit_lvl == 3 then
    counter_name = "l2_misses"
  end

  if counter_name then
    increment_counter(self, counter_name)
  end

  return "ok"
end


function _M:log_latency(latency)
  if not self:enabled() then
    return "vitals not enabled"
  end

  local bucket = self:current_bucket()

  if bucket then
    self.counters.metrics[bucket].proxy_latency_count = self.counters.metrics[bucket].proxy_latency_count + 1
    self.counters.metrics[bucket].proxy_latency_total = self.counters.metrics[bucket].proxy_latency_total + latency

    self.counters.metrics[bucket].proxy_latency_min =
      math_min(self.counters.metrics[bucket].proxy_latency_min, latency)

    self.counters.metrics[bucket].proxy_latency_max =
      math_max(self.counters.metrics[bucket].proxy_latency_max, latency)
  end

  return "ok"
end


function _M:log_upstream_latency(latency)
  if not self:enabled() then
    return "vitals not enabled"
  end

  if not latency then
    return "ok"
  end

  local bucket = self:current_bucket()
  if bucket then
    self.counters.metrics[bucket].ulat_count = self.counters.metrics[bucket].ulat_count + 1
    self.counters.metrics[bucket].ulat_total = self.counters.metrics[bucket].ulat_total + latency

    self.counters.metrics[bucket].ulat_min =
      math_min(self.counters.metrics[bucket].ulat_min, latency)

    self.counters.metrics[bucket].ulat_max =
      math_max(self.counters.metrics[bucket].ulat_max, latency)
  end

  return "ok"
end


function _M:log_request(ctx)
  if not self:enabled() then
    return "vitals not enabled"
  end

  local bucket = self:current_bucket()
  if bucket then
    self.counters.metrics[bucket].requests = self.counters.metrics[bucket].requests + 1
  end

  return "ok"
end


function _M:log_phase_after_plugins(ctx, status)
  if not self:enabled() then
    return "vitals not enabled"
  end

  if not ctx.service then
    -- we're only logging for services and routes. if there's no
    -- service on the request, don't fill up the cache with useless keys
    return true
  end

  if self.tsdb_storage then
    -- skip maintaining counters since TSDB strategies handle writes directly
    return self.strategy:log()
  end

  local seconds = time()
  local minutes = seconds - (seconds % 60)

  -- TODO: add ctx.workspace_ids and dispense with all this
  local workspaces = {}
  local i = 1

  if ctx.workspaces then
    for _, v in ipairs(ctx.workspaces) do
      workspaces[i] = v.id
      i = i + 1
    end
  end
  workspaces = table.concat(workspaces, ",")

  local key = (ctx.service and ctx.service.id or "") .. "|" ..
    (ctx.route and ctx.route.id or "") .. "|" ..
    (status or "") .. "|" ..
    (ctx.authenticated_consumer and ctx.authenticated_consumer.id or "") .. "|" ..
    workspaces .. "|"

  local key_prefixes = {
    seconds .. "|1|",
    minutes .. "|60|",
  }

  for _, kp in ipairs(key_prefixes) do
    local _, err, forced = self.counter_cache:incr(kp .. key, 1, 0)

    if forced then
      log(INFO, _log_prefix, "kong_vitals cache is full")
    elseif err then
      log(WARN, _log_prefix, "failed to increment counter: ", err)
    end
  end

  return key
end


return _M
