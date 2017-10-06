local fmt      = string.format
local log      = ngx.log
local ERR      = ngx.ERR
local DEBUG    = ngx.DEBUG
local time     = ngx.time
local math_min = math.min
local math_max = math.max


local _log_prefix = "[vitals-aggregator] "


local _M = {}
local mt = { __index = _M }


-- how long to store minutes aggregates, in seconds
local MINUTES_EXPIRY = 90000


function _M.new(opts)
  local self = {
    db = opts.db,
  }

  return setmetatable(self, mt)
end


function _M:aggregate_minutes(seconds_table)
  local q = fmt("select * from %s order by at", seconds_table)

  local seconds_rows, err = self.db:query(q)

  if err then
    return nil, "Failed to retrieve raw data. query: " .. q .. " error: " .. err
  end

  if #seconds_rows == 0 then
    log(DEBUG, _log_prefix, "No data to aggregate from table ", seconds_table)
    return true
  end

  -- find the minute that contains the earliest second we need to process
  local start_at = seconds_rows[1].at - (seconds_rows[1].at % 60)

  -- initialize accumulators
  local current_values = {
    hit      = 0,
    miss     = 0,
    plat_min = "null",
    plat_max = "null",
  }

  -- values we'll insert into the minutes table
  local rows_to_insert = {}
  local index          = 1

  -- aggregate seconds into minutes
  for i = 1, #seconds_rows do
    local row = seconds_rows[i]
    local end_before = start_at + 60

    if row.at < end_before then
      self:calculate_aggregates(current_values, row)
    else
      rows_to_insert[index] = {
        tostring(start_at),
        tostring(current_values.hit),
        tostring(current_values.miss),
        tostring(current_values.plat_min),
        tostring(current_values.plat_max),
      }

      index = index + 1

      -- re-initialize accumulators and timestamp
      current_values = {
        hit = row.l2_hit,
        miss = row.l2_miss,
        plat_min = row.plat_min or "null",
        plat_max = row.plat_max or "null",
      }

      -- TODO: Base this on current data, don't assume all minutes are populated
      start_at = start_at + 60
    end
  end

  -- add the last row we accumulated
  rows_to_insert[index] = {
    tostring(start_at),
    tostring(current_values.hit),
    tostring(current_values.miss),
    tostring(current_values.plat_min),
    tostring(current_values.plat_max),
  }

  -- insert new rows
  local q = "INSERT INTO vitals_stats_minutes (at,l2_hit,l2_miss,plat_min,plat_max) VALUES "

  for i = 1, #rows_to_insert do
    q = q .. "(" .. table.concat(rows_to_insert[i], ",") .. "),"
  end
  q = string.sub(q, 1, -2) .. " ON CONFLICT (at) DO NOTHING"

  local _, err = self.db:query(q)

  if err then
    return nil, "Failed to insert minutes. query: " .. q .. " error: " .. err
  end


  -- delete old minutes
  self:delete_before("vitals_stats_minutes", time() - MINUTES_EXPIRY)
end


function _M:calculate_aggregates(old, new)
  old.hit  = old.hit + new.l2_hit
  old.miss = old.miss + new.l2_miss

  if type(old.plat_min) == "number" and type(new.plat_min) == "number" then
    old.plat_min = math_min(old.plat_min, new.plat_min)
  else
    old.plat_min = new.plat_min or "null"
  end

  if type(old.plat_max) == "number" and type(new.plat_max) == "number" then
    old.plat_max = math_max(old.plat_max, new.plat_max)
  else
    old.plat_max = new.plat_max or "null"
  end
end


function _M:delete_before(table_name, cutoff_time)
  local q = fmt("delete from %s where at < %d", table_name, cutoff_time)

  local _, err = self.db:query(q)

  if err then
    log(ERR, _log_prefix, "Failed to delete minutes data. query: ",
        q, " error: ", err)
    return nil, err
  end
end


return _M
