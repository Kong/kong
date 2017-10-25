local cassandra = require "cassandra"


local fmt      = string.format
local floor    = math.floor
local math_min = math.min
local math_max = math.max
local time     = ngx.time
local unpack   = unpack

local _M = {}
local mt = { __index = _M }

local INSERT_STATS = [[
  INSERT INTO %s (node_id, %s, at, l2_hit, l2_miss, plat_min, plat_max)
    VALUES(?, ?, ?, ?, ?, ?, ?)
    USING TTL %d
]]

local SELECT_STATS        = "select * from vitals_stats_seconds"
local SELECT_MINUTE_STATS = "select * from vitals_stats_minutes"

local QUERY_OPTIONS = {
  prepared = true,
}


local function aggregate_seconds(acc, current_hit, current_miss, current_plat_min, current_plat_max)
  acc.hit  = acc.hit + current_hit
  acc.miss = acc.miss + current_miss

  if type(current_plat_min) == "number" then
    if type(acc.plat_min) == "number" then
      acc.plat_min = math_min(acc.plat_min, current_plat_min)
    else 
      acc.plat_min = current_plat_min
    end
  end

  if type(current_plat_max) == "number" then
    if type(acc.plat_max) == "number" then
      acc.plat_max = math_max(acc.plat_max, current_plat_max)
    else 
      acc.plat_max = current_plat_max
    end
  end
end


function _M.new(dao_factory)
  local self = {
    cluster = dao_factory.db.cluster,
    seconds_ttl = 900, -- This will eventually be set by kong.conf
    minutes_ttl = 84600, -- This will eventually be set by kong.conf
  }

  return setmetatable(self, mt)
end


function _M:init()
  return true
end


function _M:get_timestamp_str(ts)
  return tostring(ts / 1000)
end


function _M:select_stats(query_type)
  if query_type ~= "minutes" and query_type ~= "seconds" then
    return nil, "query_type must be 'minutes' or 'seconds'"
  end

  local query, res, err

  if query_type == "seconds" then
    query = fmt(SELECT_STATS)
  elseif query_type == "minutes" then
    query = fmt(SELECT_MINUTE_STATS)
  end

  res, err = self.cluster:execute(query)
  if not res then
    return nil, "could not select stats. query: " .. query .. " error: " .. err
  end

  return res
end


function _M:insert_stats(data, node_id)
  local at, hit, miss, plat_min, plat_max, query, res, err
  local cass_node_id = cassandra.uuid(node_id)
  local now = time()
  local minute = cassandra.timestamp(self:get_minute(now))
  local hour = cassandra.timestamp(self:get_hour(now))

  -- accumulator for minutes data
  local minute_acc = {
    hit      = 0,
    miss     = 0,
    plat_min = cassandra.null,
    plat_max = cassandra.null,
  }
  
  -- iterate over seconds data
  for _, row in ipairs(data) do
    at, hit, miss, plat_min, plat_max = unpack(row)
    
    plat_min = plat_min or cassandra.null
    plat_max = plat_max or cassandra.null

    -- add current second data to minute accumulator
    aggregate_seconds(minute_acc, hit, miss, plat_min, plat_max)

    query = fmt(INSERT_STATS, 'vitals_stats_seconds', 'minute', self.seconds_ttl)

    -- insert seconds row
    res, err = self.cluster:execute(query, {
      cass_node_id,
      minute,
      cassandra.timestamp(at * 1000),
      hit,
      miss,
      plat_min,
      plat_max
    }, QUERY_OPTIONS)

    if not res then
      return nil, "could not insert stats. query: " .. query .. " error: " .. err
    end
  end

  query = fmt(INSERT_STATS, 'vitals_stats_minutes', 'hour', self.minutes_ttl)

  -- insert minute row
  res, err = self.cluster:execute(query, {
    cass_node_id,
    hour,
    minute,
    minute_acc.hit,
    minute_acc.miss,
    minute_acc.plat_min,
    minute_acc.plat_max
  }, QUERY_OPTIONS)

  if not res then
    return nil, "could not insert stats. query: " .. query .. " error: " .. err
  end

  return true
end


function _M:current_table_name()
  return nil
end

function _M:get_minute(time) 
  return floor(time / 60) * 60000
end

function _M:get_hour(time)
  return floor(time / 3600) * 3600000
end

return _M
