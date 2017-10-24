local timer_at   = ngx.timer.at
local time       = ngx.time
local math_min   = math.min
local math_max   = math.max
local log        = ngx.log
local DEBUG      = ngx.DEBUG
local WARN       = ngx.WARN
local json_null  = require("cjson").null
local singletons = require "kong.singletons"


local persistence_handler

local _log_prefix = "[vitals] "

local _M = {}
local mt = { __index = _M }


function _M.new(opts)
  opts = opts or {}

  if not opts.dao then
    return error("opts.dao is required")
  end

  if opts.flush_interval and type(opts.flush_interval) ~= "number" then
    return error("opts.flush_interval must be a number")
  end

  local strategy

  do
    local db_strategy
    local dao_factory = opts.dao

    if dao_factory.db_type == "postgres" then
      db_strategy = require "kong.vitals.postgres.strategy"
    elseif dao_factory.db_type == "cassandra" then
      db_strategy = require "kong.vitals.cassandra.strategy"
    else
      return error("no vitals strategy for " .. dao_factory.db_type)
    end

    strategy = db_strategy.new(dao_factory)
  end

  local counters = {
    l2_hits           = {},
    l2_misses         = {},
    proxy_latency_min = {},
    proxy_latency_max = {},
    start_at          = 0,
  }

  local self = {
    strategy       = strategy,
    counters       = counters,
    flush_interval = opts.flush_interval,
    timer_started  = false,
  }


  return setmetatable(self, mt)
end


function _M:enabled()
  return singletons.configuration.vitals
end


function _M:init()
  if not self:enabled() then
    return "vitals not enabled"
  end

  log(DEBUG, _log_prefix, "init")
  self.strategy:init()

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
    return nil, "flush_counters() threw an error: " .. err
  end

end


-- returns formatted vitals seconds or minutes data based on the query_type
function _M:get_stats(query_type)
  local res, err = self.strategy:select_stats(query_type)

  if err then
    log(WARN, _log_prefix, err)
    return {}
  end

  return self:convert_stats(res)
end


-- converts the db query result into a standardized format for the admin API
function _M:convert_stats(res)
  local stats = {}

  -- convert [timestamp, l2_hit, l2_miss, latency_min, latency_max]
  -- to {timestamp = [hit, miss, latency_min, latency_max]}
  for _, row in ipairs(res) do
    stats[tostring(row.at)] = {
      row.l2_hit,
      row.l2_miss,
      row.plat_min or json_null,
      row.plat_max or json_null,
    }
  end

  return stats
end


function _M:flush_counters(data)
  data = data or self:prepare_counters_for_insert()

  local _, err = self.strategy:insert_stats(data)
  if err then
    return nil, err
  end

  -- reset counters table
  self:reset_counters()

  return true
end


function _M:cache_accessed(hit_lvl, key, value)
  if not self:enabled() then
    return "vitals not enabled"
  end

  if not self.timer_started then
    log(DEBUG, _log_prefix, "starting vitals timer (1)")

    local ok, err = timer_at(self.flush_interval, persistence_handler, self)
    if ok then
      self.timer_started = true
      self:reset_counters()

    else
      return nil, "failed to start recurring vitals timer (1): " .. err
    end

  end

  local counter_name

  if hit_lvl == 2 then
    counter_name = "l2_hits"
  elseif hit_lvl == 3 then
    counter_name = "l2_misses"
  end

  if counter_name then
    self:increment_counter(counter_name)
  end

  return "ok"
end


function _M:increment_counter(counter_name)
  local bucket, err = self:current_bucket()

  if bucket then
    self.counters[counter_name][bucket] = self.counters[counter_name][bucket] + 1
  else
    log(WARN, _log_prefix, err)
  end
end


function _M:current_bucket()
  local bucket = time() - self.counters.start_at + 1

  if bucket < 1 or bucket > 60 then
    return nil, "bucket " .. bucket ..
        " out of range for counters starting at " .. self.counters.start_at
  end

  return bucket
end


function _M:prepare_counters_for_insert()
  local data_to_insert = {}
  local timestamp      = self.counters.start_at

  -- last_bucket can't be more than 60 seconds from start_at
  local last_bucket = math_min(time() - timestamp, 60)

  for i = 1, last_bucket do
    data_to_insert[i] = {
      timestamp,
      self.counters.l2_hits[i],
      self.counters.l2_misses[i],
      self.counters.proxy_latency_min[i],
      self.counters.proxy_latency_max[i],
    }

    timestamp = timestamp + 1
  end

  return data_to_insert
end


function _M:reset_counters(counters)
  local counters = counters or self.counters

  counters.start_at = time()

  for i = 1, 60 do
    counters.l2_hits[i] = 0
    counters.l2_misses[i] = 0
    counters.proxy_latency_min[i] = nil
    counters.proxy_latency_max[i] = nil
  end


  return counters
end


function _M:log_latency(latency)
  if not self:enabled() then
    return "vitals not enabled"
  end

  local bucket = self:current_bucket()

  if bucket then
    self.counters.proxy_latency_min[bucket] =
      math_min(self.counters.proxy_latency_min[bucket] or 999999, latency)

    self.counters.proxy_latency_max[bucket] =
      math_max(self.counters.proxy_latency_max[bucket] or 0, latency)
  end

  return "ok"
end


return _M
