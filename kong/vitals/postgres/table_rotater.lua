local fmt        = string.format
local timer_at   = ngx.timer.at
local log        = ngx.log
local ERR        = ngx.ERR
local WARN       = ngx.WARN
local DEBUG      = ngx.DEBUG
local time       = ngx.time
local aggregator = require "kong.vitals.postgres.aggregator"


local _log_prefix = "[vitals-table-rotater] "

local _M = {}
local mt = { __index = _M }

local rotation_handler

-- 'vitals_stats_seconds' is a template table: no data will be inserted into it
local CREATE_VITALS_STATS_SECONDS = [[
  CREATE TABLE IF NOT EXISTS %s
  (LIKE vitals_stats_seconds INCLUDING defaults INCLUDING constraints INCLUDING indexes);
]]

-- all vitals_stats_seconds_* tables with names prior to the current one
-- (so that we don't drop current or next table)
-- NOTE: Can't use string.format here because it interprets the
-- LIKE matcher (%) as an invalid string interpolation symbol
-- TODO: Make this a prepared statement, if possible in pgmoon
local SELECT_PREVIOUS_VITALS_STATS_SECONDS = [[
    select table_name from information_schema.tables
     where table_schema = 'public'
       and table_name like 'vitals_stats_seconds_%'
       and table_name < ]]

local DROP_PREVIOUS_VITALS_STATS_SECONDS = "DROP TABLE IF EXISTS %s"

local NO_PREVIOUS_TABLE = "No previous table"


function _M.new(opts)

  local self = {
    db = opts.db,
    rotation_interval = opts.rotation_interval,
    aggregator = aggregator.new(opts),
  }

  return setmetatable(self, mt)
end


rotation_handler = function(premature, self)
  if premature then
    return
  end


  local _, err = timer_at(self.rotation_interval / 60, rotation_handler, self)
  if err then
    log(ERR, _log_prefix, "failed to start rotater timer (2): ", err)
    return
  end


  local _, err = self:create_next_table()
  if err then
    -- don't return here -- still want to try to drop previous table(s)
    log(ERR, _log_prefix, "create_next_table() threw an error: ", err)
  end


  local _, err = self:drop_previous_table()
  if err then
    log(ERR, _log_prefix, "drop_previous_table() threw an error: ", err)
  end
end


function _M:init()
  -- make sure we have a current vitals_stats_seconds table
  local query = fmt(CREATE_VITALS_STATS_SECONDS, self:current_table_name())
  local res, query_err = self.db:query(query)
  if not res then
    return nil, "could not create vitals_stats_seconds table: " .. query_err
  end

  -- start a timer to make the next table
  local ok, err = timer_at(self.rotation_interval / 60, rotation_handler, self)
  if ok then
    ok, err = self:create_next_table()

    if not ok then
      return nil, "failed to create next table: " .. err
    end

  else
    return nil, "failed to start rotater timer (1):" .. err
  end

  return true

end


function _M:current_table_name()
  local now              = time()
  local current_interval = now - (now % self.rotation_interval)

  return "vitals_stats_seconds_" .. current_interval
end

--[[
  returns the current table name and the previous table name (if previous table exists)
  data: [ current_table_name, previous_table_name ]
 ]]
function _M:table_names_for_select()
  local current_table_name = self:current_table_name()

  local q = SELECT_PREVIOUS_VITALS_STATS_SECONDS .. "'" .. current_table_name ..
            "'" .. " order by table_name desc limit 1"

  log(DEBUG, _log_prefix, q)

  local previous_table, err = self.db:query(q)

  if err then
    return err
  elseif previous_table[1] then
    return { current_table_name, previous_table[1].table_name }
  else
    return { current_table_name }
  end
end


function _M:create_next_table()
  local now           = time()
  local next_interval = now - (now % self.rotation_interval) + self.rotation_interval
  local table_name    = "vitals_stats_seconds_" .. next_interval

  local query = fmt(CREATE_VITALS_STATS_SECONDS, table_name)

  log(DEBUG, _log_prefix, query)

  local ok, err = self.db:query(query)

  if not ok then
    return nil, err
  end

  return table_name
end


--[[
  only drop tables before the previous table. If the previous table doesn't
  exist, then return and don't drop tables.
]]
function _M:drop_previous_table()
  local previous_table

  local ok, err = self:table_names_for_select()

  if err then
    return nil, "Failed to select tables. error: " .. err
  elseif ok[2] then
    previous_table = ok[2]
  else
    return nil, NO_PREVIOUS_TABLE
  end

  local q = SELECT_PREVIOUS_VITALS_STATS_SECONDS .. "'" .. previous_table .. "'"

  log(DEBUG, _log_prefix, q)

  local select_res, select_err = self.db:query(q)

  if select_err then
    return nil, "Failed to select tables. query: " .. q .. ". error: " .. select_err
  end

  for i = 1, #select_res do
    local row = select_res[i]
    local seconds_table = row.table_name

    local _, err = self.aggregator:aggregate_minutes(seconds_table)

    if err then
      return nil, "Failed to aggregate minutes for " .. seconds_table ..
          ". error: " .. err
    end

    q = fmt(DROP_PREVIOUS_VITALS_STATS_SECONDS, row.table_name)

    log(DEBUG,_log_prefix,  q)

    local _, err = self.db:query(q)

    if err then
      log(WARN, _log_prefix, "Failed to drop table ", row.table_name, err)
    end
  end
end


return _M
