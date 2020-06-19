--[[
CREATE TABLE rl_counters(
  namespace    text,
  window_start timestamp,
  window_size  int,
  key          text,
  count        counter,
  PRIMARY KEY((namespace, window_start, window_size), key)
);
--]]

local cassandra = require "cassandra"


local time         = ngx.time
local ngx_log      = ngx.log
local ERR          = ngx.ERR
local floor        = math.floor
local type         = type
local tonumber     = tonumber
local setmetatable = setmetatable
local new_tab
do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function(narr, nrec) return {} end
  end
end


local function window_floor(size, time)
  return floor(time / size) * size
end


local INCR_COUNTER_QUERY = [[
UPDATE rl_counters
   SET count = count + ?
 WHERE namespace    = ?
   AND window_start = ?
   AND window_size  = ?
   AND key          = ?
]]


local SELECT_COUNTER_QUERY = [[
SELECT * FROM rl_counters
 WHERE namespace    = ?
   AND window_start = ?
   AND window_size  = ?
   AND key          = ?
]]
local SELECT_COUNTER_OPTIONS = {
  prepared = true,
}


local SELECT_COUNTERS_IN_WINDOW_QUERY = [[
SELECT * FROM rl_counters
 WHERE namespace    = ?
   AND window_start = ?
   AND window_size  = ?
]]
local SELECT_COUNTERS_IN_WINDOW_OPTIONS = {
  prepared = true,
}

local DELETE_COUNTER_QUERY = [[
DELETE FROM rl_counters
  WHERE namespace = ?
    AND window_size = ?
    AND window_start IN ?
]]

local select_counter_args            = new_tab(4, 0)
local select_counters_in_window_args = new_tab(3, 0)
local cluster


local function log(lvl, ...)
  ngx_log(lvl, "[rate-limiting][cassandra strategy] ", ...)
end


local _M = {}
local mt = { __index = _M }


function _M.new(db)
  local self = {
    cluster = db.connector.cluster,
  }

  cluster = self.cluster

  return setmetatable(self, mt)
end


--[[
local diffs = {
  {
    key = "1.2.3.4",
    windows = {
      {
        namespace = "foo",
        window = 123456778,
        size   = 60,
        diff   = 5,
      },
      {
        namespace = "bar",
        window = 123456778,
        size   = 5,
        diff   = 1,
      },
    }
  },
  {
    -- ...
  }
}
--]]
function _M:push_diffs(diffs)
  if type(diffs) ~= "table" then
    error("diffs must be a table", 2)
  end

  for i = 1, #diffs do
    local key       = diffs[i].key
    local windows   = diffs[i].windows
    local n_windows = #windows

    -- update counters of all windows for this key
    local c_key   = key

    for j = 1, n_windows do
      -- build args for this increment query
      local c_diff   = cassandra.counter(windows[j].diff)
      local c_window = cassandra.timestamp(windows[j].window)

      -- update current key counter for current windows
      local res, err = self.cluster:execute(
        INCR_COUNTER_QUERY, 
        {
          c_diff,
          windows[j].namespace,
          c_window,
          windows[j].size,
          c_key,
        } 
      )
      if not res then
        log(ERR, "failed to increment diff counters: ", err)
      end  
    end
  end
end


local function counters_for_window(namespace, window_start, window_size)
  -- bind query args

  select_counters_in_window_args[1] = namespace
  select_counters_in_window_args[2] = cassandra.timestamp(window_start)
  select_counters_in_window_args[3] = tonumber(window_size)

  -- retrieve via paginated SELECT query

  local counters     = new_tab(2^6, 0) -- very arbitrary initial slot allocation
  local counters_idx = 0

  for rows, err in cluster:iterate(SELECT_COUNTERS_IN_WINDOW_QUERY,
                                   select_counters_in_window_args,
                                   SELECT_COUNTERS_IN_WINDOW_OPTIONS) do
    if err then
      log(ERR, "failed to retrieve counters for window (", namespace, "|",
               window_size, "|", window_start, "): ", err)
      return nil
    end

    for i = 1, #rows do
      counters_idx = counters_idx + 1
      counters[counters_idx] = rows[i]
    end
  end

  return counters
end


local function next_window(windows, namespace, i)
  i = i + 1

  local window = windows[i]
  if not window then
    return nil
  end

  local rows = counters_for_window(namespace, window.start, window.size)
  if not rows or #rows == 0 then
    return next_window(windows, namespace, i)
  end

  return rows, i
end


local function iter(self)
  if not self.rows then
    self.rows, self.windows_idx = next_window(self.windows, self.namespace,
                                              self.windows_idx)
    if not self.rows then
      -- no more windows to iterate over
      return nil
    end

    self.rows_idx = 0
  end

  self.rows_idx  = self.rows_idx + 1
  local row = self.rows[self.rows_idx]
  if not row then
    -- we ended our iteration on this key's rows
    -- next key is up
    self.rows = nil
    return iter(self)
  end

  return row
end


do
  local iter_mt = { __call = iter }

  function _M:get_counters(namespace, window_sizes, cur_time)
    cur_time = cur_time or time()

    local windows

    do
      local windows_idx = 0
      local n_windows   = #window_sizes

      windows = new_tab(n_windows, 0)

      for i = 1, n_windows do
        local w_start      = window_floor(window_sizes[i], cur_time)
        local prev_w_start = w_start - window_sizes[i]

        windows[windows_idx + 1] = { start = w_start,      size = window_sizes[i] }
        windows[windows_idx + 2] = { start = prev_w_start, size = window_sizes[i] }
        windows_idx = windows_idx + 2
      end
    end

    local iter_ctx = {
      windows      = windows,
      namespace    = namespace,
      windows_idx  = 0,
      rows_idx     = 0,
      --rows       = nil,
    }

    return setmetatable(iter_ctx, iter_mt)
  end
end


function _M:get_window(key, namespace, window_start, window_size)
  -- build args

  select_counter_args[1] = namespace
  select_counter_args[2] = cassandra.timestamp(window_start)
  select_counter_args[3] = window_size
  select_counter_args[4] = key

  -- retrieve our counter

  local rows, err = self.cluster:execute(SELECT_COUNTER_QUERY,
                                         select_counter_args,
                                         SELECT_COUNTER_OPTIONS)
  if not rows then
    return nil, "failed to retrieve window for key/namespace (" .. key ..
                "/" .. namespace .. "): " .. err
  end

  if #rows ~= 1 then
    return nil, "failed to retrieve window for key/namespace (" .. key ..
                "/" .. namespace .. "): found " .. #rows .. " rows instead of 1"
  end

  return rows[1].count
end


-- get lists of window start values for the past hour for each
-- window size
function _M.get_window_start_lists(window_sizes, now)
  local window_starts_per_size = new_tab(#window_sizes, 0)

  for _, window_size in ipairs(window_sizes) do
    local last_obsolete_window_start = window_floor(window_size, now) - 2 * window_size
    -- clean up last hour of counters, which covers the maintenance cycle
    -- time window
    local number_windows_last_hour = floor(3600 / window_size)
    local window_starts = new_tab(number_windows_last_hour, 0)

    for i=1, number_windows_last_hour do
      window_starts[i] = cassandra.timestamp(last_obsolete_window_start)
      last_obsolete_window_start = last_obsolete_window_start - window_size
    end

    window_starts_per_size[window_size] = window_starts
  end

  return window_starts_per_size
end

local function delete_obsolete_rows(cluster, namespace, window_sizes, time)
  local window_starts = _M.get_window_start_lists(window_sizes, time)
  local success = true
  local errs = {}

  for _, window_size in ipairs(window_sizes) do
    local _, err = cluster:execute(DELETE_COUNTER_QUERY, {
      namespace,
      window_size,
      window_starts[window_size],
    })

    if err then
      success = false
      errs[#errs + 1] = err
    end
  end

  return success and success or nil, errs
end


function _M:purge(namespace, window_sizes, time)
  local ok, errs = delete_obsolete_rows(self.cluster, namespace, window_sizes, time)
  if not ok then
    log(ERR, "failed to purge obsolete counters: ", table.concat(errs, ", "))
    return false
  end

  return true
end


return _M
