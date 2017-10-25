local table_rotater_module = require "kong.vitals.postgres.table_rotater"
local fmt                  = string.format
local unpack               = unpack


local _M = {}
local mt = { __index = _M }


local INSERT_STATS = [[
  insert into %s (at, l2_hit, l2_miss, plat_min, plat_max) values (%d, %d, %d, %s, %s)
  on conflict (at) do update set
    l2_hit = %s.l2_hit + excluded.l2_hit,
    l2_miss = %s.l2_miss + excluded.l2_miss,
    plat_min = least(%s.plat_min, excluded.plat_min),
    plat_max = greatest(%s.plat_max, excluded.plat_max)
]]

local SELECT_STATS = "select * from %s order by at desc limit 60"

local SELECT_MINUTE_STATS = "select * from vitals_stats_minutes order by at desc"


function _M.new(dao_factory)
  local table_rotater = table_rotater_module.new(
    {
      db = dao_factory.db,
      rotation_interval = 3600,
    }
  )

  local self = {
    db = dao_factory.db,
    table_rotater = table_rotater,
  }

  return setmetatable(self, mt)
end


function _M:init()
  self.table_rotater:init()
end


--[[
  returns the last 60 rows from the previous and current vitals_stats_seconds
  tables if query_type is seconds.

  returns all rows in the vitals_stats_minutes table
  if query_type is minutes.

  TODO: make interval length configurable
 ]]
function _M:select_stats(query_type)
  if query_type ~= "minutes" and query_type ~= "seconds" then
    return nil, "query_type must be 'minutes' or 'seconds'"
  end

  local query, res, err, table_names

  if query_type == "seconds" then
    table_names, err = self:table_names_for_select()

    if err then
      return nil, err
    elseif table_names[2] then
      -- union query from previous and current seconds tables
      query = fmt("select * from %s union " .. SELECT_STATS, table_names[2], table_names[1])
    else
      -- query only from current seconds table
      query = fmt(SELECT_STATS, table_names[1])
    end
  elseif query_type == "minutes" then
    query = fmt(SELECT_MINUTE_STATS)
  end

  res, err = self.db:query(query)
  if not res then
    return nil, "could not select stats. query: " .. query .. " error: " .. err
  end

  return res
end


--[[
  constructs an insert statement for each row in data. If there's already a row
  with this timestamp, aggregates appropriately per stat type
  TODO: this function exits on first error. Make this more robust
  TODO: optimize inserts (use bulk insert instead of _n_ separate ones)

  data: a 2D-array of [
    [timestamp, l2_hits, l2_misses, proxy_latency_min, proxy_latency_max],
    [timestamp, l2_hits, l2_misses, proxy_latency_min, proxy_latency_max],
    ...
  ]
]]
function _M:insert_stats(data)

  local at, hit, miss, plat_min, plat_max, query, res, err
  local table_name = self:current_table_name()

  for _, row in ipairs(data) do
    at, hit, miss, plat_min, plat_max = unpack(row)

    plat_min = plat_min or "null"
    plat_max = plat_max or "null"

    query = fmt(INSERT_STATS, table_name, at, hit, miss, plat_min, plat_max,
                table_name, table_name, table_name, table_name)

    res, err = self.db:query(query)

    if not res then
      return nil, "could not insert stats. query: " .. query .. " error: " .. err
    end
  end

  return true
end

function _M:get_timestamp_str(ts) 
  return tostring(ts)
end

function _M:current_table_name()
  return self.table_rotater:current_table_name()
end

function _M:table_names_for_select()
  return self.table_rotater:table_names_for_select()
end


return _M
