local concat       = table.concat
local floor        = math.floor
local ngx_time     = ngx.time
local ngx_log      = ngx.log
local ERR          = ngx.ERR
local type         = type
local setmetatable = setmetatable
local new_tab
do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function(narr, nrec) return {} end
  end
end


local DELETE_COUNTER_QUERY = [[
DELETE
   FROM rl_counters
  WHERE namespace    = ?
    AND window_start <= ?
    AND window_size  = ?
]]

local INCR_COUNTER_QUERY = [[
INSERT INTO rl_counters
  (key, namespace, window_start, window_size, count)
  VALUES (?, ?, ?, ?, ?)
  ON CONFLICT(key, namespace, window_start, window_size) DO
  UPDATE
  SET count = rl_counters.count + ?;
]]

local SELECT_SYNC_KEYS_QUERY = [[
SELECT  *
   FROM rl_counters
  WHERE namespace    =   ?
    AND window_start IN (?)
]]

local SELECT_WINDOW_QUERY = [[
SELECT  *
   FROM rl_counters
  WHERE key          = ?
    AND namespace    = ?
    AND window_start = ?
    AND window_size  = ?
]]


local function log(lvl, ...)
  ngx_log(lvl, "[rate-limiting] ", ...)
end

local function window_floor(size, time)
  return floor(time / size) * size
end

local _M = {}


function _M.new(db)
  return setmetatable(
    {
      db = db.connector,
    },
    {
      __index = _M,
    }
  )
end


local function escape(val)
  if type(val) == "string" then
    val = "'" .. tostring((val:gsub("'", "''"))) .. "'"
  end

  return val
end

local function bind(stmt, params)
  if type(stmt) ~= "string" then
    error("stmt must be a psql query string", 2)
  end

  if type(params) ~= "table" then
    error("params must be provided as a table", 2)
  end

  for i = 1, #params do
    stmt = stmt:gsub('%?', escape(params[i]), 1)
  end

  return stmt
end


function _M:push_diffs(diffs)
  if type(diffs) ~= "table" then
    error("diffs must be a table", 2)
  end

  local num_diffs = #diffs
  local query_tab = new_tab(num_diffs, 0) -- assume num_diffs windows per key
  local query_tab_idx = 1

  -- if no diffs, nothing to do, return...
  if num_diffs == 0 then
    return
  end

  do
    local param_tab = new_tab(6, 0)

    for i = 1, num_diffs do
      local key     = diffs[i].key
      local windows = diffs[i].windows

      for j = 1, #diffs[i].windows do
        param_tab[1] = key
        param_tab[2] = windows[j].namespace
        param_tab[3] = windows[j].window
        param_tab[4] = windows[j].size
        param_tab[5] = windows[j].diff
        param_tab[6] = windows[j].diff

        local q = bind(INCR_COUNTER_QUERY, param_tab)

        query_tab[query_tab_idx] = q
        query_tab_idx = query_tab_idx + 1
      end
    end

  end

  -- each of these are individual queries, but we can batch them together
  local res, err = self.db:query(concat(query_tab, '; '))
  if not res then
    log(ERR, "failed to upsert counter values: ", err)
  end
end


function _M:get_counters(namespace, window_sizes, time)
  time = time or ngx_time()
  local window_starts = {}

  do
    local window_starts_idx = 0

    for i = 1, #window_sizes do
      local start = window_floor(window_sizes[i], time)
      local prev_start = start - window_sizes[i]

      if not window_starts[start] then
        window_starts[start] = true
        window_starts_idx = window_starts_idx + 1
        window_starts[window_starts_idx] = start
      end

      if not window_starts[prev_start] then
        window_starts[prev_start] = true
        window_starts_idx = window_starts_idx + 1
        window_starts[window_starts_idx] = prev_start
      end
    end
  end

  -- bind the namespace, we'll handle our IN array separately
  local q = bind(SELECT_SYNC_KEYS_QUERY, { namespace })
  q = q:gsub('%?', concat(window_starts, ", "), 1)

  local rows, err = self.db:query(q)
  if not rows then
    log(ERR, "failed to select sync keys for namespace ", namespace, ": ", err)
    return
  end

  local row_idx = 0
  local num_rows = #rows

  local function iter()
    row_idx = row_idx + 1
    if row_idx <= num_rows then
      return rows[row_idx]
    end
  end

  return iter
end


function _M:get_window(key, namespace, window_start, window_size)
  local param_tab = new_tab(4, 0)

  param_tab[1] = key
  param_tab[2] = namespace
  param_tab[3] = window_start
  param_tab[4] = window_size

  local q = bind(SELECT_WINDOW_QUERY, param_tab)

  local rows, err = self.db:query(q)
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


function _M:purge(namespace, window_sizes, window_start)
  if not window_start then
    window_start = ngx_time()
  end

  local query_tab = new_tab(#window_sizes, 0)
  local query_tab_idx = 1

  do
    local param_tab = new_tab(3, 0)
    param_tab[1] = namespace
    for _, window_size in ipairs(window_sizes) do
      param_tab[2] = window_start - window_size * 2
      param_tab[3] = window_size

      query_tab[query_tab_idx] = bind(DELETE_COUNTER_QUERY, param_tab)
      query_tab_idx = query_tab_idx + 1
    end
  end

  -- each of these are individual queries, but we can batch them together
  local res, err = self.db:query(concat(query_tab, '; '))
  if not res then
    log(ERR, "failed to delete counters: ", err)
    return false
  end

  return true
end


return _M
