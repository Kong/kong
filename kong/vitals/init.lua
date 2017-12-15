local utils      = require "kong.tools.utils"
local json_null  = require("cjson").null
local singletons = require "kong.singletons"
local pg_strat   = require "kong.vitals.postgres.strategy"
local ffi        = require "ffi"


local timer_at   = ngx.timer.at
local time       = ngx.time
local sleep      = ngx.sleep
local math_min   = math.min
local math_max   = math.max
local log        = ngx.log
local DEBUG      = ngx.DEBUG
local WARN       = ngx.WARN
local ERR        = ngx.ERR

local consumers_dict = ngx.shared.kong_vitals_requests_consumers

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


local persistence_handler
local _log_prefix = "[vitals] "
local NODE_ID_KEY = "vitals:node_id"


local FLUSH_LOCK_KEY = "vitals:flush_lock"
local FLUSH_LIST_KEY = "vitals:flush_list:"


local worker_count = ngx.worker.count()


local _M = {}
local mt = { __index = _M }

--[[
  use signed ints to support sentinel values on "max" stats e.g.,
  proxy and upstream max latencies
]]
ffi.cdef[[
  typedef uint32_t time_t;

  typedef struct vitals_metrics_s {
    uint32_t    l2_hits;
    uint32_t    l2_misses;
    uint32_t    proxy_latency_min;
    int32_t     proxy_latency_max;
    uint32_t    ulat_min;
    int32_t     ulat_max;
    uint32_t    requests;
    time_t      timestamp;
  } vitals_metrics_t;
]]


local vitals_metrics_t_arr_type  = ffi.typeof("vitals_metrics_t[?]")
local vitals_metrics_t_size      = ffi.sizeof("vitals_metrics_t")
local const_vitals_metrics_t_ptr = ffi.typeof("const vitals_metrics_t*")


--[[
  generate the initializers for an array of vitals_metrics_t structs
  of size `sz`. this table will be fed as the third param of the ffi.new()
  call to generate our vitals_metrics_t[?]. the first two elements are
  initialized to 0, as they are just incrementing counters. the third and
  fourth initializers (for proxy_latency_min and proxy_latency_max,
  respectively) serve as sentinel values. we call math.min/max on these values
  so they must be initialized to some value that is handle in Lua land as a
  number. when we prepare to push stats to our strategy, we check for the
  presence of this sentinel value; if it exists, we never called the path to
  which the values are associated, meaning that the vitals strategy expects
  these to be nil. the final element is the timestamp associated with the
  bucket
]]
local function metrics_t_arr_init(sz)
  local t = new_tab(sz, 0)

  local timestamp = time()

  for i = 1, sz do
    t[i] = { 0, 0, 0xFFFFFFFF, -1, 0xFFFFFFFF, -1, 0, timestamp + i - 1 }
  end

  return t
end


function _M.new(opts)
  opts = opts or {}

  if not opts.dao then
    return error("opts.dao is required")
  end

  if opts.flush_interval                   and
     type(opts.flush_interval) ~= "number" and
     opts.flush_interval % 1 ~= 0          then
    return error("opts.flush_interval must be an integer")
  end

  local strategy

  do
    local db_strategy
    local dao_factory = opts.dao

    local strategy_opts = {
      ttl_seconds = opts.ttl_seconds or 3600,
      ttl_minutes = opts.ttl_minutes or 90000,
    }

    if dao_factory.db_type == "postgres" then
      db_strategy = pg_strat
    elseif dao_factory.db_type == "cassandra" then
      db_strategy = require "kong.vitals.cassandra.strategy"
    else
      return error("no vitals strategy for " .. dao_factory.db_type)
    end

    strategy = db_strategy.new(dao_factory, strategy_opts)
  end

  -- paradoxically, we set flush_interval to a very high default here,
  -- so that tests won't attempt to flush counters as a side effect.
  -- in a normal Kong scenario, opts.flush interval will be
  -- initialized from configuration.
  local self = {
    shm            = ngx.shared.kong,
    strategy       = strategy,
    counters       = {},
    flush_interval = opts.flush_interval or 90000,
    ttl_seconds    = opts.ttl_seconds or 3600,
    ttl_minutes    = opts.ttl_minutes or 90000,
    initialized    = false,
  }

  return setmetatable(self, mt)
end


function _M:enabled()
  return singletons.configuration.vitals and self.initialized
end


function _M:init()
  if not singletons.configuration.vitals then
    return "vitals not enabled"
  end

  log(DEBUG, _log_prefix, "init")

  -- set node id (uuid) on shm
  local ok, err = self.shm:safe_add(NODE_ID_KEY, utils.uuid())
  if not ok and err ~= "exists" then
    return nil,  "failed to set 'node_id' in shm: " .. err
  end

  local node_id, err = self.shm:get(NODE_ID_KEY)
  if err then
    return nil, "failed to get 'node_id' from shm: " .. err
  end

  if not node_id then
    return nil, "no 'node_id' set in shm"
  end

  local delay = self.flush_interval
  local when  = delay - (ngx.now() - (math.floor(ngx.now() / delay) * delay))
  log(DEBUG, _log_prefix, "starting vitals timer (1) (", when, ") seconds")

  local ok, err = timer_at(when, persistence_handler, self)
  if ok then
    self:reset_counters()
  else
    return nil, "failed to start recurring vitals timer (1): " .. err
  end

  -- init strategy, recording node id and hostname in db
  local ok, err = self.strategy:init(node_id, utils.get_hostname())
  if not ok then
    return nil, "failed to init vitals strategy " .. err
  end

  self.initialized = true

  return "ok"
end


persistence_handler = function(premature, self)
  if premature then
    -- we could flush counters now
    return
  end

  log(DEBUG, _log_prefix, "starting vitals timer (2)")

  local ok, err = timer_at(self.flush_interval, persistence_handler, self)
  if not ok then
    return nil, "failed to start recurring vitals timer (2): " .. err
  end

  local _, err = self:flush_counters()
  if err then
    log(ERR, _log_prefix, "flush_counters() threw an error: ", err)
  end
end


local function parse_dictionary_key(key)
  -- split on |
  local p = key:find("|", 1, true)
  local id = key:sub(1, p - 1)
  p = p + 1
  local timestamp = tonumber(key:sub(p))

  return id, timestamp
end


-- converts Kong stats to format expected by Vitals API
local function convert_stats(vitals, res)
  local stats = {}

  for _, row in ipairs(res) do
    stats[row.node_id] = stats[row.node_id] or {}

    stats[row.node_id][vitals.strategy:get_timestamp_str(row.at)] = {
      row.l2_hit,
      row.l2_miss,
      row.plat_min or json_null,
      row.plat_max or json_null,
      row.ulat_min or json_null,
      row.ulat_max or json_null,
      row.requests,
    }
  end

  return stats
end


-- converts customer stats to format expected by Vitals API
local function convert_customer_stats(vitals, res)
  local stats = {}

  for _, row in ipairs(res) do
    stats[row.node_id] = stats[row.node_id] or {}
    stats[row.node_id][vitals.strategy:get_timestamp_str(row.at)] = row.count
  end

  return stats
end


local function build_flush_key(vitals)
  local timestamp = time()

  -- hack around minor timing differences among worker processes. its possible
  -- that some workers start the recurring timer at slightly before the
  -- floor timestamp of our flush interval. to account for this we check
  -- manually to ensure that, if we did hit an off-by-one condition, we will
  -- still associated this push with the correct timestamp.
  --
  -- TODO this whole situation can be avoided by synchronizing the flush key
  -- amongst the node workers via worker events
  if timestamp % vitals.flush_interval ~= 0 then
    log(DEBUG, _log_prefix, "tried to build flush key at invalid timestamp")

    if (timestamp + 1) % vitals.flush_interval == 0 then
      log(DEBUG, _log_prefix, "cheat timestamp up 1 sec")
      timestamp = timestamp + 1
    end
  end

  return FLUSH_LIST_KEY .. timestamp
end


-- acquire a lock for flushing counters to the database
function _M:flush_lock()
  local ok, err = self.shm:safe_add(FLUSH_LOCK_KEY, true,
    self.flush_interval - 0.01)
  if not ok then
    if err ~= "exists" then
      log(ERR, "failed to acquire vitals flush lock: ", err)
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

    local num_posted, err = self.shm:llen(flush_key)
    if err then
      return nil, err
    end

    log(DEBUG, _log_prefix, "found ", num_posted, " workers posted data")

    if num_posted == expected then
      break
    end

    i = i + 1
    if i > 10 then
      return nil, "timeout waiting for workers to post vitals data"
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
  for i = 1, worker_count do
    local v, err = self.shm:rpop(flush_key)

    if not v then
      return nil, err
    end

    local vitals_metrics_t = ffi.cast(const_vitals_metrics_t_ptr, v)

    for i = 1, self.flush_interval do
      local c = vitals_metrics_t[i - 1]

      -- this is an expected condition, particularly the first time a worker
      -- flushes data
      if time() - c.timestamp < 1 then
        log(DEBUG, _log_prefix, "timestamp overrun at idx ", i)
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
      local plat_min = f and f[4] and math_min(f[4], c.proxy_latency_min) or
                  c.proxy_latency_min

      -- the same logic applies for max as did for min
      local plat_max = f and f[5] and math_max(f[5], c.proxy_latency_max) or
                  c.proxy_latency_max

      -- upstream latency: same logic as for proxy latency
      local ulat_min = f and f[6] and math_min(f[6], c.ulat_min) or
          c.ulat_min

      local ulat_max = f and f[7] and math_max(f[7], c.ulat_max) or
          c.ulat_max

      local requests = f and f[8] + c.requests or c.requests

      flush_data[i] = {
        c.timestamp,
        l2_hits,
        l2_misses,
        plat_min,
        plat_max,
        ulat_min,
        ulat_max,
        requests,
      }

      if flush_data[i][4] == 0xFFFFFFFF then
        flush_data[i][4] = nil
        flush_data[i][5] = nil
      end

      if flush_data[i][6] == 0xFFFFFFFF then
        flush_data[i][6] = nil
        flush_data[i][7] = nil
      end
    end
  end

  self.shm:delete(flush_key)

  return flush_data
end


function _M:flush_consumer_counters()
  log(DEBUG, _log_prefix, "flushing consumer counters")
  local keys = consumers_dict:get_keys()
  local data = new_tab(#keys, 0)

  -- keep track of consumers whose stale data we'll delete
  local consumers = {}

  for i, key in ipairs(keys) do
    local count, err = consumers_dict:get(key)

    if count then
      consumers_dict:delete(key) -- trust that the insert will succeed

      local id, timestamp = parse_dictionary_key(key)
      data[i] = { id, timestamp, 1, count }

      consumers[id] = true

    elseif err then
      log(WARN, _log_prefix, "failed to fetch ", key, ". err: ", err)

    else
      log(DEBUG, _log_prefix, key, " not found")
    end
  end

  -- insert data if there is any
  if data[1] then
    local ok, err = self.strategy:insert_consumer_stats(data)
    if not ok then
      log(WARN, _log_prefix, "failed to save consumer stats: ", err)
    end
  end

  -- clean up old data
  local now = time()
  local cutoff_times = {
    seconds = now - self.ttl_seconds,
    minutes = now - self.ttl_minutes,
  }
  local ok, err = self.strategy:delete_consumer_stats(consumers, cutoff_times)
  if not ok then
    log(WARN, _log_prefix, "failed to delete consumer stats: ", err)
  end
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
    log(DEBUG, _log_prefix, flush_key)

    local ok, err = self.shm:rpush(flush_key, buf)
    if not ok then
      -- this is likely an OOM error, dont want to stop processing here
      log(ERR, _log_prefix, "error attempting to push to list: ", err)
    end
  end

  -- reset counters table. this applies to all workers
  self:reset_counters()

  -- if we're in charge of pushing to the strategy, lets hang tight for a bit
  -- and wait for each worker to push up their data. we will then coallese it
  -- into the data form that vitals strategies expect
  if lock then
    log(DEBUG, "acquired flush lock on pid ", ngx.worker.pid())
    local ok, err = self:poll_worker_data(flush_key)
    if not ok then
      -- timeout while polling data
      return nil, err
    end

    log(DEBUG, _log_prefix, "merging worker data")
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
    self:flush_consumer_counters()
  end

  log(DEBUG, _log_prefix, "flush done")

  return true
end


local function increment_counter(vitals, counter_name)
  local bucket, err = vitals:current_bucket()

  if bucket then
    vitals.counters.metrics[bucket][counter_name] = vitals.counters.metrics[bucket][counter_name] + 1
  else
    log(DEBUG, _log_prefix, err)
  end
end


function _M:reset_counters(counters)
  local counters = counters or self.counters

  counters.start_at = time()
  counters.metrics  = ffi.new(vitals_metrics_t_arr_type, self.flush_interval,
                        metrics_t_arr_init(self.flush_interval))

  return counters
end


function _M:current_bucket()
  local bucket = time() - self.counters.start_at

  if bucket < 0 or bucket > self.flush_interval - 1 then
    return nil, "bucket " .. bucket ..
        " out of range for counters starting at " .. self.counters.start_at
  end

  return bucket
end


--[[
                         FOR THE VITALS API
  Functions in this section are called by the Vitals (Admin) API.
 ]]
function _M:get_index()

  local data = {}

  local stat_labels = {
    "cache_datastore_hits_total",
    "cache_datastore_misses_total",
    "latency_proxy_request_min_ms",
    "latency_proxy_request_max_ms",
    "latency_upstream_min_ms",
    "latency_upstream_max_ms",
    "requests_proxy_total",
    "requests_consumer_total",
  }

  data.stats = {}

  for i, stat in ipairs(stat_labels) do
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

    data.stats[stat] = {
      levels = levels_data,
    }
  end

  return data
end


function _M:get_stats(query_type, level, node_id)
  if query_type ~= "minutes" and query_type ~= "seconds" then
    return nil, "Invalid query params: interval must be 'minutes' or 'seconds'"
  end

  if level ~= "cluster" and level ~= "node" then
    return nil, "Invalid query params: level must be 'cluster' or 'node'"
  end


  if not utils.is_valid_uuid(node_id) and node_id ~= nil then
    return nil, "Invalid query params: invalid node_id"
  end

  local res, err = self.strategy:select_stats(query_type, level, node_id)

  if err then
    log(WARN, _log_prefix, err)
    return {}
  end

  return convert_stats(self, res)
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
    return nil, "Invalid query params: duration must be 'minutes' or 'seconds'"
  end

  if opts.level ~= "node" and opts.level ~= "cluster" then
    return nil, "Invalid query params: level must be 'node' or 'cluster'"
  end

  if opts.node_id and not utils.is_valid_uuid(opts.node_id) then
    return nil, "Invalid query params: invalid node_id"
  end

  local query_opts = {
    consumer_id = opts.consumer_id,
    duration    = opts.duration == "seconds" and 1 or 60,
    level       = opts.level,
    node_id     = opts.node_id,
  }

  local res, _ = self.strategy:select_consumer_stats(query_opts)

  if not res then
    return nil, "Failed to retrieve stats for consumer " .. opts.consumer_id
  end

  local retval = {
    meta = {
      interval = opts.duration,
      consumer = {
        id = opts.consumer_id,
      },
    },
    stats = convert_customer_stats(self, res)
  }

  if opts.node_id then
    retval.meta.node = {
      id = opts.node_id,
    }
  end

  return retval
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
function _M.table_names(dao)

  -- tables common across both dbs
  local table_names = {
    "vitals_consumers",
    "vitals_node_meta",
    "vitals_stats_hours",
    "vitals_stats_minutes",
    "vitals_stats_seconds",
  }
  local table_count = #table_names

  if dao.db_type == "postgres" then
    -- pick up the tables created at runtime
    for i, v in ipairs(pg_strat.dynamic_table_names(dao)) do
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
    log(DEBUG, _log_prefix, "upstream latency is required")
    return "ok"
  end

  local bucket = self:current_bucket()
  if bucket then
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

  if not ctx then
    -- this won't happen in normal processing
    ctx = {}
  end

  local retval = "ok"

  local bucket = self:current_bucket()
  if bucket then
    self.counters.metrics[bucket].requests = self.counters.metrics[bucket].requests + 1
  end

  if ctx.authenticated_consumer then
    local key = ctx.authenticated_consumer.id .. "|" .. time()
    local ok, err, forced_eviction = consumers_dict:incr(key, 1, 0)

    if forced_eviction then
      log(WARN, _log_prefix, "kong_vitals_requests_consumers cache is full")
    elseif err then
      log(WARN, _log_prefix, "log_request() failed: ", err)
    end

    if ok then
      -- handy for testing
      retval = key
    end
  end

  return retval
end


function _M:node_exists(node_id)
  if not utils.is_valid_uuid(node_id) then
    return nil, "node_id is not a valid UUID"
  end

  local res, _ = self.strategy:check_node(node_id)

  if not res[1] then
    return nil, "node does not exist"
  end

  return true
end

return _M
