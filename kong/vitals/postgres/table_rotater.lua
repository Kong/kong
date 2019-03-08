local fmt        = string.format
local match      = string.match
local timer_at   = ngx.timer.at
local log        = ngx.log
local WARN       = ngx.WARN
local DEBUG      = ngx.DEBUG
local time       = ngx.time


local _log_prefix = "[vitals-table-rotater] "

local _M = {}
local mt = { __index = _M }

local rotation_handler

-- 'vitals_stats_seconds' is a template table: no data will be inserted into it
local CREATE_VITALS_STATS_SECONDS = [[
  CREATE TABLE IF NOT EXISTS %s
  (LIKE vitals_stats_seconds INCLUDING defaults INCLUDING constraints INCLUDING indexes);
]]

-- all vitals_stats_seconds_* tables with names prior to the given one
-- (so that we don't drop current or next table)
-- NOTE: Can't use string.format here because it interprets the
-- LIKE matcher (%) as an invalid string interpolation symbol
local SELECT_PREVIOUS_VITALS_STATS_SECONDS = [[
    select table_name from information_schema.tables
     where table_schema = 'public'
       and table_name like 'vitals_stats_seconds_%'
       and table_name < '?'
       order by table_name desc]]

local DROP_PREVIOUS_VITALS_STATS_SECONDS = "DROP TABLE IF EXISTS %s"

local TABLE_NAMES_FOR_SELECT = [[
    SELECT tablename FROM pg_tables WHERE tablename IN ('%s', '%s')
    ORDER BY tablename DESC
]]


function _M.new(opts)
  if not opts.connector then
    error "opts.connector is required"
  end

  local self = {
    connector = opts.connector,
    rotation_interval = opts.ttl_seconds or 3600,
  }

  return setmetatable(self, mt)
end


rotation_handler = function(premature, self)
  if premature then
    return
  end


  -- we need a new table every `rotation_interval` seconds. Set timer
  -- to run twice more frequently, giving us >1 chance to create
  -- the table before we need it.
  local _, err = timer_at(self.rotation_interval / 2, rotation_handler, self)
  if err then
    log(WARN, _log_prefix, "failed to start rotater timer (2): ", err)
    return
  end


  local _, err = self:create_next_table()
  if err then
    -- don't return here -- still want to try to drop previous table(s)
    log(WARN, _log_prefix, "create_next_table() threw an error: ", err)
  end


  local _, err = self:drop_previous_table()
  if err then
    log(WARN, _log_prefix, err)
  end
end


function _M:init()
  -- make sure we have a current vitals_stats_seconds table
  local query = fmt(CREATE_VITALS_STATS_SECONDS, self:current_table_name())
  local _, err = self.connector:query(query)

  if err and not match(tostring(err), "exists") then
    -- if the error isn't "table already exists", it's a real problem
    return nil, "could not create current table: " .. err
  end

  -- start a timer to make the next table
  local ok, err = timer_at(self.rotation_interval / 2, rotation_handler, self)
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

  local now = time()

  local previous_interval = now - (now % self.rotation_interval) - self.rotation_interval

  local previous_table_name = "vitals_stats_seconds_" .. previous_interval

  local res, err = self.connector:query(fmt(TABLE_NAMES_FOR_SELECT, current_table_name,
                                     previous_table_name))
  if err then
    return nil, err
  end

  local table_names_for_select = {}
  if res[2] then
    -- both tables exist
    table_names_for_select = { current_table_name, previous_table_name }
  elseif res[1] then
    -- only current table exists
    table_names_for_select = { current_table_name }
  end

  return table_names_for_select
end


function _M:create_missing_seconds_table(table_name)
  local query = fmt(CREATE_VITALS_STATS_SECONDS, table_name)
  local _, err = self.connector:query(query)

  if err and not match(tostring(err), "exists") then
    return nil, "could not create missing table: " .. table_name .. " err: " .. err
  end

  return table_name
end


function _M:create_next_table()
  local now           = time()
  local next_interval = now - (now % self.rotation_interval) + self.rotation_interval
  local table_name    = "vitals_stats_seconds_" .. next_interval

  local query = fmt(CREATE_VITALS_STATS_SECONDS, table_name)

  log(DEBUG, _log_prefix, query)

  local _, err = self.connector:query(query)

  if err and not match(tostring(err), "exists") then
    return nil, "could not create next table: " .. err
  end

  return table_name
end


-- drop tables we aren't currently querying from
function _M:drop_previous_table()
  -- the oldest table name we query from is two rotation intervals ago.
  -- this could become dynamic if rotation interval and retention period diverge.
  local timestamp = time() - (2 * self.rotation_interval)
  local prior_to = "vitals_stats_seconds_" .. tostring(timestamp)
  local q = SELECT_PREVIOUS_VITALS_STATS_SECONDS:gsub('?', prior_to)

  log(DEBUG, _log_prefix, q)

  local table_names, err = self.connector:query(q)

  if err then
    return nil, "Failed to select tables. query: " .. q .. ". error: " .. tostring(err)
  end

  for _, row in ipairs(table_names) do
    q = fmt(DROP_PREVIOUS_VITALS_STATS_SECONDS, row.table_name)

    log(DEBUG,_log_prefix,  q)

    local _, err = self.connector:query(q)

    if err then
      log(WARN, _log_prefix, "Failed to drop table ", row.table_name, tostring(err))
    end
  end
end


return _M
