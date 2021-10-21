--- @module Prometheus
--
-- vim: ts=2:sw=2:sts=2:expandtab:textwidth=80
-- This module uses a single dictionary shared between Nginx workers to keep
-- all metrics. Each metric is stored as a separate entry in that dictionary.
--
-- In addition, each worker process has a separate set of counters within
-- its lua runtime that are used to track increments to count metrics, and
-- are regularly flushed into the main shared dictionary. This is a performance
-- optimization that allows counters to be incremented without locking the
-- shared dictionary. It also means that counter increments are "eventually
-- consistent"; it can take up to a single counter sync interval (which
-- defaults to 1 second) for counter values to be visible for collection.
--
-- Prometheus requires that (a) all samples for a given metric are presented
-- as one uninterrupted group, and (b) buckets of a histogram appear in
-- increasing numerical order. We satisfy that by carefully constructing full
-- metric names (i.e. metric name along with all labels) so that they meet
-- those requirements while being sorted alphabetically. In particular:
--
--  * all labels for a given metric are presented in reproducible order (the one
--    used when labels were declared). "le" label for histogram metrics always
--    goes last;
--  * bucket boundaries (which are exposed as values of the "le" label) are
--    stored as floating point numbers with leading and trailing zeroes,
--    and those zeros would be removed just before we expose the metrics;
--  * internally "+Inf" bucket is stored as "Inf" (to make it appear after
--    all numeric buckets), and gets replaced by "+Inf" just before we
--    expose the metrics.
--
-- For example, if you define your bucket boundaries as {0.00005, 10, 1000}
-- then we will keep the following samples for a metric `m1` with label
-- `site` set to `site1`:
--
--   m1_bucket{site="site1",le="0000.00005"}
--   m1_bucket{site="site1",le="0010.00000"}
--   m1_bucket{site="site1",le="1000.00000"}
--   m1_bucket{site="site1",le="Inf"}
--   m1_count{site="site1"}
--   m1_sum{site="site1"}
--
-- And when exposing the metrics, their names will be changed to:
--
--   m1_bucket{site="site1",le="0.00005"}
--   m1_bucket{site="site1",le="10"}
--   m1_bucket{site="site1",le="1000"}
--   m1_bucket{site="site1",le="+Inf"}
--   m1_count{site="site1"}
--   m1_sum{site="site1"}
--
-- You can find the latest version and documentation at
-- https://github.com/knyar/nginx-lua-prometheus
-- Released under MIT license.

-- This library provides per-worker counters used to store counter metric
-- increments. Copied from https://github.com/Kong/lua-resty-counter
local resty_counter_lib = require("prometheus_resty_counter")

local Prometheus = {}
local mt = { __index = Prometheus }

local TYPE_COUNTER    = 0x1
local TYPE_GAUGE      = 0x2
local TYPE_HISTOGRAM  = 0x4
local TYPE_LITERAL = {
  [TYPE_COUNTER]   = "counter",
  [TYPE_GAUGE]     = "gauge",
  [TYPE_HISTOGRAM] = "histogram",
}

-- Default name for error metric incremented by this library.
local DEFAULT_ERROR_METRIC_NAME = "nginx_metric_errors_total"

-- Default value for per-worker counter sync interval (seconds).
local DEFAULT_SYNC_INTERVAL = 1

-- Default set of latency buckets, 5ms to 10s:
local DEFAULT_BUCKETS = {0.005, 0.01, 0.02, 0.03, 0.05, 0.075, 0.1, 0.2, 0.3,
                         0.4, 0.5, 0.75, 1, 1.5, 2, 3, 4, 5, 10}


-- Accepted range of byte values for tailing bytes of utf8 strings.
-- This is defined outside of the validate_utf8_string function as a const
-- variable to avoid creating and destroying table frequently.
-- Values in this table (and in validate_utf8_string) are from table 3-7 of
-- www.unicode.org/versions/Unicode6.2.0/UnicodeStandard-6.2.pdf
local accept_range = {
  {lo = 0x80, hi = 0xBF},
  {lo = 0xA0, hi = 0xBF},
  {lo = 0x80, hi = 0x9F},
  {lo = 0x90, hi = 0xBF},
  {lo = 0x80, hi = 0x8F}
}

-- Validate utf8 string for label values.
--
-- Args:
--   str: string
--
-- Returns:
--   (bool) whether the input string is a valid utf8 string.
--   (number) position of the first invalid byte.
local function validate_utf8_string(str)
  local i, n = 1, #str
  local first, byte, left_size, range_idx
  while i <= n do
    first = string.byte(str, i)
    if first >= 0x80 then
      range_idx = 1
      if first >= 0xC2 and first <= 0xDF then -- 2 bytes
        left_size = 1
      elseif first >= 0xE0 and first <= 0xEF then -- 3 bytes
        left_size = 2
        if first == 0xE0 then
          range_idx = 2
        elseif first == 0xED then
          range_idx = 3
        end
      elseif first >= 0xF0 and first <= 0xF4 then -- 4 bytes
        left_size = 3
        if first == 0xF0 then
          range_idx = 4
        elseif first == 0xF4 then
          range_idx = 5
        end
      else
        return false, i
      end

      if i + left_size > n then
        return false, i
      end

      for j = 1, left_size do
        byte = string.byte(str, i + j)
        if byte < accept_range[range_idx].lo or byte > accept_range[range_idx].hi then
          return false, i
        end
        range_idx = 1
      end
      i = i + left_size
    end
    i = i + 1
  end
  return true
end

-- Generate full metric name that includes all labels.
--
-- Args:
--   name: string
--   label_names: (array) a list of label keys.
--   label_values: (array) a list of label values.
--
-- Returns:
--   (string) full metric name.
local function full_metric_name(name, label_names, label_values)
  if not label_names then
    return name
  end
  local label_parts = {}
  for idx, key in ipairs(label_names) do
    local label_value
    if type(label_values[idx]) == "string" then
      local valid, pos = validate_utf8_string(label_values[idx])
      if not valid then
        label_value = string.sub(label_values[idx], 1, pos - 1)
                        :gsub("\\", "\\\\")
                        :gsub('"', '\\"')
      else
        label_value = label_values[idx]
                        :gsub("\\", "\\\\")
                        :gsub('"', '\\"')
      end
    else
      label_value = tostring(label_values[idx])
    end
    table.insert(label_parts, key .. '="' .. label_value .. '"')
  end
  return name .. "{" .. table.concat(label_parts, ",") .. "}"
end

-- Extract short metric name from the full one.
--
-- This function is only used by Prometheus:metric_data.
--
-- Args:
--   full_name: (string) full metric name that can include labels.
--
-- Returns:
--   (string) short metric name with no labels. For a `*_bucket` metric of
--     histogram the _bucket suffix will be removed.
local function short_metric_name(full_name)
  local labels_start, _ = full_name:find("{")
  if not labels_start then
    return full_name
  end
  -- Try to detect if this is a histogram metric. We only check for the
  -- `_bucket` suffix here, since it alphabetically goes before other
  -- histogram suffixes (`_count` and `_sum`).
  local suffix_idx, _ = full_name:find("_bucket{")
  if suffix_idx and full_name:find("le=") then
    -- this is a histogram metric
    return full_name:sub(1, suffix_idx - 1)
  end
  -- this is not a histogram metric
  return full_name:sub(1, labels_start - 1)
end

-- Check metric name and label names for correctness.
--
-- Regular expressions to validate metric and label names are
-- documented in https://prometheus.io/docs/concepts/data_model/
--
-- Args:
--   metric_name: (string) metric name.
--   label_names: label names (array of strings).
--
-- Returns:
--   Either an error string, or nil of no errors were found.
local function check_metric_and_label_names(metric_name, label_names)
  if not metric_name:match("^[a-zA-Z_:][a-zA-Z0-9_:]*$") then
    return "Metric name '" .. metric_name .. "' is invalid"
  end
  for _, label_name in ipairs(label_names or {}) do
    if label_name == "le" then
      return "Invalid label name 'le' in " .. metric_name
    end
    if not label_name:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then
      return "Metric '" .. metric_name .. "' label name '" .. label_name ..
             "' is invalid"
    end
  end
end

-- Construct bucket format for a list of buckets.
--
-- This receives a list of buckets and returns a sprintf template that should
-- be used for bucket boundaries to make them come in increasing order when
-- sorted alphabetically.
--
-- To re-phrase, this is where we detect how many leading and trailing zeros we
-- need.
--
-- Args:
--   buckets: a list of buckets
--
-- Returns:
--   (string) a sprintf template.
local function construct_bucket_format(buckets)
  local max_order = 1
  local max_precision = 1
  for _, bucket in ipairs(buckets) do
    assert(type(bucket) == "number", "bucket boundaries should be numeric")
    -- floating point number with all trailing zeros removed
    local as_string = string.format("%f", bucket):gsub("0*$", "")
    local dot_idx = as_string:find(".", 1, true)
    max_order = math.max(max_order, dot_idx - 1)
    max_precision = math.max(max_precision, as_string:len() - dot_idx)
  end
  return "%0" .. (max_order + max_precision + 1) .. "." .. max_precision .. "f"
end

-- Format bucket format when exposing metrics.
--
-- This function removes leading and trailing zeroes from `le` label values.
--
-- Args:
--   key: the metric key
--
-- Returns:
--   (string) the formatted key
local function fix_histogram_bucket_labels(key)
  local part1, bucket, part2 = key:match('(.*[,{]le=")(.*)(".*)')
  if part1 == nil then
    return key
  end

  if bucket == "Inf" then
    return table.concat({part1, "+Inf", part2})
  else
    return table.concat({part1, tostring(tonumber(bucket)), part2})
  end
end

-- Return a full metric name for a given metric+label combination.
--
-- This function calculates a full metric name (or, in case of a histogram
-- metric, several metric names) for a given combination of label values. It
-- stores the result in a tree of tables used as a cache (self.lookup) and
-- uses that cache to return results faster.
--
-- Args:
--   self: a `metric` object, created by register().
--   label_values: a list of label values.
--
-- Returns:
--   - If `self` is a counter or a gauge: full metric name as a string.
--   - If `self` is a histogram metric: a list of strings:
--     [0]: full name of the _count histogram metric;
--     [1]: full name of the _sum histogram metric;
--     [...]: full names of each _bucket metrics.
local function lookup_or_create(self, label_values)
  -- If one of the `label_values` is nil, #label_values will return the number
  -- of non-nil labels in the beginning of the list. This will make us return an
  -- error here as well.
  local cnt = label_values and #label_values or 0
  -- specially, if first element is nil, # will treat it as "non-empty"
  if cnt ~= self.label_count or (self.label_count > 0 and not label_values[1]) then
    return nil, string.format("inconsistent labels count, expected %d, got %d",
                              self.label_count, cnt)
  end
  local t = self.lookup
  if label_values then
    -- Don't use ipairs here to avoid inner loop generates trace first
    -- Otherwise the inner for loop below is likely to get JIT compiled before
    -- the outer loop which include `lookup_or_create`, in this case the trace
    -- for outer loop will be aborted. By not using ipairs, we will be able to
    -- compile longer traces as possible.
    local label
    for i=1, self.label_count do
      label = label_values[i]
      if not t[label] then
        t[label] = {}
      end
      t = t[label]
    end
  end

  local LEAF_KEY = mt -- key used to store full metric names in leaf tables.
  local full_name = t[LEAF_KEY]
  if full_name then
    return full_name
  end

  if self.typ == TYPE_HISTOGRAM then
    -- Pass empty metric name to full_metric_name to just get the formatted
    -- labels ({key1="value1",key2="value2",...}).
    local labels = full_metric_name("", self.label_names, label_values)
    full_name = {
      self.name .. "_count" .. labels,
      self.name .. "_sum" .. labels,
    }

    local bucket_pref
    if self.label_count > 0 then
      -- strip last }
      bucket_pref = self.name .. "_bucket" .. string.sub(labels, 1, #labels-1) .. ","
    else
      bucket_pref = self.name .. "_bucket{"
    end

    for i, buc in ipairs(self.buckets) do
      full_name[i+2] = string.format("%sle=\"%s\"}", bucket_pref, self.bucket_format:format(buc))
    end
    -- Last bucket. Note, that the label value is "Inf" rather than "+Inf"
    -- required by Prometheus. This is necessary for this bucket to be the last
    -- one when all metrics are lexicographically sorted. "Inf" will get replaced
    -- by "+Inf" in Prometheus:metric_data().
    full_name[self.bucket_count+3] = string.format("%sle=\"Inf\"}", bucket_pref)
  else
    full_name = full_metric_name(self.name, self.label_names, label_values)
  end
  t[LEAF_KEY] = full_name
  return full_name
end

-- Increment a gauge metric.
--
-- Gauges are incremented in the dictionary directly to provide strong ordering
-- of inc() and set() operations.
--
-- Args:
--   self: a `metric` object, created by register().
--   value: numeric value to increment by. Can be negative.
--   label_values: a list of label values, in the same order as label keys.
local function inc_gauge(self, value, label_values)
  local k, err, _
  k, err = lookup_or_create(self, label_values)
  if err then
    self._log_error(err)
    return
  end

  _, err, _ = self._dict:incr(k, value, 0)
  if err then
    self._log_error_kv(k, value, err)
  end
end

local ERR_MSG_COUNTER_NOT_INITIALIZED = "counter not initialized! " ..
  "Have you called Prometheus:init() from the " ..
  "init_worker_by_lua_block nginx phase?"

-- Increment a counter metric.
--
-- Counters are incremented in the per-worker counter, which will eventually get
-- flushed into the global shared dictionary.
--
-- Args:
--   self: a `metric` object, created by register().
--   value: numeric value to increment by. Can be negative.
--   label_values: a list of label values, in the same order as label keys.
local function inc_counter(self, value, label_values)
  -- counter is not allowed to decrease
  if value and value < 0 then
    self._log_error_kv(self.name, value, "Value should not be negative")
    return
  end

  local k, err
  k, err = lookup_or_create(self, label_values)
  if err then
    self._log_error(err)
    return
  end

  local c = self._counter
  if not c then
    c = self.parent._counter
    if not c then
      self._log_error(ERR_MSG_COUNTER_NOT_INITIALIZED)
      return
    end
    self._counter = c
  end
  c:incr(k, value)
end

-- Delete a counter or a gauge metric.
--
-- Args:
--   self: a `metric` object, created by register().
--   label_values: a list of label values, in the same order as label keys.
local function del(self, label_values)
  local k, _, err
  k, err = lookup_or_create(self, label_values)
  if err then
    self._log_error(err)
    return
  end

  -- `del` might be called immediately after a configuration change that stops a
  -- given metric from being used, so we cannot guarantee that other workers
  -- don't have unflushed counter values for a metric that is about to be
  -- deleted. We wait for `sync_interval` here to ensure that those values are
  -- synced (and deleted from worker-local counters) before a given metric is
  -- removed.
  -- Gauge metrics don't use per-worker counters, so for gauges we don't need to
  -- wait for the counter to sync.
  if self.typ ~= TYPE_GAUGE then
    ngx.log(ngx.INFO, "waiting ", self.parent.sync_interval, "s for counter to sync")
    ngx.sleep(self.parent.sync_interval)
  end

  _, err = self._dict:delete(k)
  if err then
    self._log_error("Error deleting key: ".. k .. ": " .. err)
  end
end

-- Set the value of a gauge metric.
--
-- Args:
--   self: a `metric` object, created by register().
--   value: numeric value.
--   label_values: a list of label values, in the same order as label keys.
local function set(self, value, label_values)
  if not value then
    self._log_error("No value passed for " .. self.name)
    return
  end

  local k, _, err
  k, err = lookup_or_create(self, label_values)
  if err then
    self._log_error(err)
    return
  end
  _, err = self._dict:safe_set(k, value)
  if err then
    self._log_error_kv(k, value, err)
  end
end

-- Record a given value in a histogram.
--
-- Args:
--   self: a `metric` object, created by register().
--   value: numeric value to record. Should be defined.
--   label_values: a list of label values, in the same order as label keys.
local function observe(self, value, label_values)
  if not value then
    self._log_error("No value passed for " .. self.name)
    return
  end

  local keys, err = lookup_or_create(self, label_values)
  if err then
    self._log_error(err)
    return
  end

  local c = self._counter
  if not c then
    c = self.parent._counter
    if not c then
      self._log_error(ERR_MSG_COUNTER_NOT_INITIALIZED)
      return
    end
    self._counter = c
  end

  -- _count metric.
  c:incr(keys[1], 1)

  -- _sum metric.
  c:incr(keys[2], value)

  local seen = false
  -- check in reverse order, otherwise we will always
  -- need to traverse the whole table.
  for i=self.bucket_count, 1, -1 do
    if value <= self.buckets[i] then
      c:incr(keys[2+i], 1)
      seen = true
    elseif seen then
      break
    end
  end
  -- the last bucket (le="Inf").
  c:incr(keys[self.bucket_count+3], 1)
end

-- Delete all metrics for a given gauge, counter or a histogram.
--
-- This is like `del`, but will delete all time series for all previously
-- recorded label values.
--
-- Args:
--   self: a `metric` object, created by register().
local function reset(self)
  -- Wait for other worker threads to sync their counters before removing the
  -- metric (please see `del` for a more detailed comment).
  -- Gauge metrics don't use per-worker counters, so for gauges we don't need to
  -- wait for the counter to sync.
  if self.typ ~= TYPE_GAUGE then
    ngx.log(ngx.INFO, "waiting ", self.parent.sync_interval, "s for counter to sync")
    ngx.sleep(self.parent.sync_interval)
  end

  local keys = self._dict:get_keys(0)
  local name_prefixes = {}
  local name_prefix_length_base = #self.name
  if self.typ == TYPE_HISTOGRAM then
    if self.label_count == 0 then
      name_prefixes[self.name .. "_count"] = name_prefix_length_base + 6
      name_prefixes[self.name .. "_sum"] = name_prefix_length_base + 4
    else
      name_prefixes[self.name .. "_count{"] = name_prefix_length_base + 7
      name_prefixes[self.name .. "_sum{"] = name_prefix_length_base + 5
    end
    name_prefixes[self.name .. "_bucket{"] = name_prefix_length_base + 8
  else
    name_prefixes[self.name .. "{"] = name_prefix_length_base + 1
  end

  for _, key in ipairs(keys) do
    local value, err = self._dict:get(key)
    if value then
      -- For a metric to be deleted its name should either match exactly, or
      -- have a prefix listed in `name_prefixes` (which ensures deletion of
      -- metrics with label values).
      local remove = key == self.name
      if not remove then
        for name_prefix, name_prefix_length in pairs(name_prefixes) do
          if name_prefix == string.sub(key, 1, name_prefix_length) then
            remove = true
            break
          end
        end
      end
      if remove then
        local _, err = self._dict:safe_set(key, nil)
        if err then
          self._log_error("Error resetting '", key, "': ", err)
        end
      end
    else
      self._log_error("Error getting '", key, "': ", err)
    end
  end

  -- Clean up the full metric name lookup table as well.
  self.lookup = {}
end

-- Initialize the module.
--
-- This should be called once from the `init_by_lua` section in nginx
-- configuration.
--
-- Args:
--   dict_name: (string) name of the nginx shared dictionary which will be
--     used to store all metrics
--   prefix: (optional string) if supplied, prefix is added to all
--     metric names on output
--
-- Returns:
--   an object that should be used to register metrics.
function Prometheus.init(dict_name, options_or_prefix)
  if ngx.get_phase() ~= 'init' and ngx.get_phase() ~= 'init_worker' and
      ngx.get_phase() ~= 'timer' then
    error('Prometheus.init can only be called from ' ..
      'init_by_lua_block, init_worker_by_lua_block or timer' , 2)
  end

  local self = setmetatable({}, mt)
  dict_name = dict_name or "prometheus_metrics"
  self.dict_name = dict_name
  self.dict = ngx.shared[dict_name]
  if self.dict == nil then
    error("Dictionary '" .. dict_name .. "' does not seem to exist. " ..
      "Please define the dictionary using `lua_shared_dict`.", 2)
  end

  if type(options_or_prefix) == "table" then
    self.prefix = options_or_prefix.prefix or ''
    self.error_metric_name = options_or_prefix.error_metric_name or
      DEFAULT_ERROR_METRIC_NAME
    self.sync_interval = options_or_prefix.sync_interval or
      DEFAULT_SYNC_INTERVAL
  else
    self.prefix = options_or_prefix or ''
    self.error_metric_name = DEFAULT_ERROR_METRIC_NAME
    self.sync_interval = DEFAULT_SYNC_INTERVAL
  end

  self.registry = {}

  self.initialized = true

  self:counter(self.error_metric_name, "Number of nginx-lua-prometheus errors")
  self.dict:set(self.error_metric_name, 0)

  if ngx.get_phase() == 'init_worker' then
    self:init_worker(self.sync_interval)
  end
  return self
end

-- Initialize the worker counter.
--
-- This can call this function from the `init_worker_by_lua` if you are calling
-- Prometheus.init() from `init_by_lua`, but this is deprecated. Instead, just
-- call Prometheus.init() from `init_worker_by_lua_block` and pass sync_interval
-- as part of the `options` argument if you need.
--
-- Args:
--   sync_interval: per-worker counter sync interval (in seconds).
function Prometheus:init_worker(sync_interval)
  if ngx.get_phase() ~= 'init_worker' then
    error('Prometheus:init_worker can only be called in ' ..
      'init_worker_by_lua_block', 2)
  end
  if self._counter then
    ngx.log(ngx.WARN, 'init_worker() has been called twice. ' ..
      'Please do not explicitly call init_worker. ' ..
      'Instead, call Prometheus:init() in the init_worker_by_lua_block')
    return
  end
  self.sync_interval = sync_interval or DEFAULT_SYNC_INTERVAL
  local counter_instance, err = resty_counter_lib.new(
      self.dict_name, self.sync_interval)
  if err then
    error(err, 2)
  end
  self._counter = counter_instance
end

-- Register a new metric.
--
-- Args:
--   self: a Prometheus object.
--   name: (string) name of the metric. Required.
--   help: (string) description of the metric. Will be used for the HELP
--     comment on the metrics page. Optional.
--   label_names: array of strings, defining a list of metrics. Optional.
--   buckets: array if numbers, defining bucket boundaries. Only used for
--     histogram metrics.
--   typ: metric type (one of the TYPE_* constants).
--
-- Returns:
--   a new metric object.
local function register(self, name, help, label_names, buckets, typ)
  if not self.initialized then
    ngx.log(ngx.ERR, "Prometheus module has not been initialized")
    return
  end

  local err = check_metric_and_label_names(name, label_names)
  if err then
    self:log_error(err)
    return
  end

  local name_maybe_historgram = name:gsub("_bucket$", "")
                                    :gsub("_count$", "")
                                    :gsub("_sum$", "")
  if (typ ~= TYPE_HISTOGRAM and (
      self.registry[name] or self.registry[name_maybe_historgram]
    )) or
    (typ == TYPE_HISTOGRAM and (
      self.registry[name] or
      self.registry[name .. "_count"] or
      self.registry[name .. "_sum"] or self.registry[name .. "_bucket"]
    )) then

    self:log_error("Duplicate metric " .. name)
    return
  end

  local metric = {
    name = name,
    help = help,
    typ = typ,
    label_names = label_names,
    label_count = label_names and #label_names or 0,
    -- Lookup is a tree of lua tables that contain label values, with leaf
    -- tables containing full metric names. For example, given a metric
    -- `http_count` and labels `host` and `status`, it might contain the
    -- following values:
    -- ['me.com']['200'][LEAF_KEY] = 'http_count{host="me.com",status="200"}'
    -- ['me.com']['500'][LEAF_KEY] = 'http_count{host="me.com",status="500"}'
    -- ['my.net']['200'][LEAF_KEY] = 'http_count{host="my.net",status="200"}'
    -- ['my.net']['500'][LEAF_KEY] = 'http_count{host="my.net",status="500"}'
    lookup = {},
    parent = self,
    -- Store a reference for logging functions for faster lookup.
    _log_error = function(...) self:log_error(...) end,
    _log_error_kv = function(...) self:log_error_kv(...) end,
    _dict = self.dict,
    reset = reset,
  }
  if typ < TYPE_HISTOGRAM then
    if typ == TYPE_GAUGE then
      metric.set = set
      metric.inc = inc_gauge
    else
      metric.inc = inc_counter
    end
    metric.del = del
  else
    metric.observe = observe
    metric.buckets = buckets or DEFAULT_BUCKETS
    metric.bucket_count = #metric.buckets
    metric.bucket_format = construct_bucket_format(metric.buckets)
  end

  self.registry[name] = metric
  return metric
end

-- Public function to register a counter.
function Prometheus:counter(name, help, label_names)
  return register(self, name, help, label_names, nil, TYPE_COUNTER)
end

-- Public function to register a gauge.
function Prometheus:gauge(name, help, label_names)
  return register(self, name, help, label_names, nil, TYPE_GAUGE)
end

-- Public function to register a histogram.
function Prometheus:histogram(name, help, label_names, buckets)
  return register(self, name, help, label_names, buckets, TYPE_HISTOGRAM)
end

-- Prometheus compatible metric data as an array of strings.
--
-- Returns:
--   Array of strings with all metrics in a text format compatible with
--   Prometheus.
function Prometheus:metric_data()
  if not self.initialized then
    ngx.log(ngx.ERR, "Prometheus module has not been initialized")
    return
  end

  -- Force a manual sync of counter local state (mostly to make tests work).
  self._counter:sync()

  local keys = self.dict:get_keys(0)
  -- Prometheus server expects buckets of a histogram to appear in increasing
  -- numerical order of their label values.
  table.sort(keys)

  local seen_metrics = {}
  local output = {}
  for _, key in ipairs(keys) do
    local value, err = self.dict:get(key)
    if value then
      local short_name = short_metric_name(key)
      if not seen_metrics[short_name] then
        local m = self.registry[short_name]
        if m then
          if m.help then
            table.insert(output, string.format("# HELP %s%s %s\n",
            self.prefix, short_name, m.help))
          end
          if m.typ then
            table.insert(output, string.format("# TYPE %s%s %s\n",
              self.prefix, short_name, TYPE_LITERAL[m.typ]))
          end
        end
        seen_metrics[short_name] = true
      end
      key = fix_histogram_bucket_labels(key)
      table.insert(output, string.format("%s%s %s\n", self.prefix, key, value))
    else
      self:log_error("Error getting '", key, "': ", err)
    end
  end
  return output
end

-- Present all metrics in a text format compatible with Prometheus.
--
-- This function should be used to expose the metrics on a separate HTTP page.
-- It will get the metrics from the dictionary, sort them, and expose them
-- aling with TYPE and HELP comments.
function Prometheus:collect()
  ngx.header["Content-Type"] = "text/plain"
  ngx.print(self:metric_data())
end

-- Log an error, incrementing the error counter.
function Prometheus:log_error(...)
  ngx.log(ngx.ERR, ...)
  self.dict:incr(self.error_metric_name, 1, 0)
end

-- Log an error that happened while setting up a dictionary key.
function Prometheus:log_error_kv(key, value, err)
  self:log_error(
    "Error while setting '", key, "' to '", value, "': '", err, "'")
end

return Prometheus
