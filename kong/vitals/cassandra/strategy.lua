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

local RECORD_NODE = [[
  INSERT INTO vitals_node_meta (node_id, first_report, last_report, hostname)
    VALUES(?, ?, ?, ?) IF NOT EXISTS
]]

local UPDATE_NODE = [[
  UPDATE vitals_node_meta
    SET last_report = ?
    WHERE node_id = ?
]]

local SELECT_NODES = "SELECT node_id FROM vitals_node_meta"

local SELECT_NODE = "SELECT node_id FROM vitals_node_meta WHERE node_id = ?"

local SELECT_STATS = [[
  SELECT * FROM vitals_stats_seconds
    WHERE node_id IN ?
    AND minute IN ?
]]

local SELECT_MINUTE_STATS = [[
  SELECT * FROM vitals_stats_minutes
    WHERE node_id IN ?
    AND hour IN ?
]]

local INSERT_CONSUMER_STATS = [[
  UPDATE vitals_consumers
     SET count       = count + ?
   WHERE at          = ?
     AND duration    = ?
     AND consumer_id = ?
     AND node_id     = ?
]]

local QUERY_OPTIONS = {
  prepared = true,
}

local COUNTER_QUERY_OPTIONS = {
  prepared = true,
  counter  = true,
}


local function aggregate_stats(acc, current_hit, current_miss, current_plat_min, current_plat_max)
  acc.l2_hit  = acc.l2_hit + current_hit
  acc.l2_miss = acc.l2_miss + current_miss

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


local function aggregate_cluster(stats)
  local timestamp_to_index = {}
  local cluster_stats = {}

  for _, row in ipairs(stats) do
    -- if first time seeing this timestamp...
    if not timestamp_to_index[row.at] then
      -- insert a new accumulator in the cluster_stats array
      table.insert(cluster_stats, {
        at       = row.at,
        l2_hit   = 0,
        l2_miss  = 0,
        plat_min = nil,
        plat_max = nil,
        node_id = "cluster"
      })

      -- save its index in the timestamp_to_index hash
      timestamp_to_index[row.at] = #cluster_stats
    end
    
    -- add the current row to the accumulator
    aggregate_stats(cluster_stats[timestamp_to_index[row.at]], row.l2_hit, row.l2_miss, row.plat_min, row.plat_max)
  end

  return cluster_stats
end


function _M.new(dao_factory, opts)
  if not opts then
    opts = {}
  end

  local self = {
    cluster     = dao_factory.db.cluster,
    seconds_ttl = opts.ttl_seconds or 3600,
    minutes_ttl = opts.ttl_minutes or 90000,
    node_id     = nil,
  }

  return setmetatable(self, mt)
end


function _M:init(node_id, hostname)
  if not node_id then
    return nil, "node_id is required"
  end

  self.node_id = cassandra.uuid(node_id)

  local now = cassandra.timestamp(time() * 1000)

  local res, err = self.cluster:execute(RECORD_NODE, {
    self.node_id,
    now,
    now,
    hostname
  }, QUERY_OPTIONS)

  if not res then
    return nil, "could not record node meta data. query: " .. RECORD_NODE .. " error: " .. err
  end

  return true
end


function _M:get_timestamp_str(ts)
  return tostring(ts / 1000)
end


function _M:select_stats(query_type, level, node_id)
  local query, buckets, res, err
  local now = time()
  local node_ids = {}

  -- If node_id is nil (cluster level or node level with nil node_id passed)
  -- Query db for list of nodes
  if node_id == nil then
    res, err = self.cluster:execute(SELECT_NODES)
    
    if not res then
      return nil, "could not select nodes. query: " .. SELECT_NODES .. " error: " .. err
    end

    -- map the node ids to array, cast to cassandra uuid
    for i = 1, #res do
      node_ids[i] = cassandra.uuid(res[i].node_id)
    end

  else 
    -- otherwise, we have a single requested node_id
    node_ids[1] = cassandra.uuid(node_id)
  end

  -- construct query
  if query_type == "seconds" then
    -- seconds, we query for the current minute and the previous minute
    buckets = {
      cassandra.timestamp(self:get_minute(now - 60)),
      cassandra.timestamp(self:get_minute(now))
    }
    query = SELECT_STATS
  elseif query_type == "minutes" then
    -- for minutes, we query for the current hour and the previous hour
    buckets = {
      cassandra.timestamp(self:get_hour(now - 3600)),
      cassandra.timestamp(self:get_hour(now))
    }
    query = SELECT_MINUTE_STATS
  end

  -- TODO: handle multiple node ids, currently only one nodes data will be visible after
  --   mapping in the calling function (vitals.lua)
  res, err = self.cluster:execute(query, {
      node_ids,
      buckets
    }, QUERY_OPTIONS)

  if not res then
    return nil, "could not select stats. query: " .. query .. " error: " .. err
  end

  -- if cluster level, aggregate stats into a single node_id key "cluster"
  if level == "cluster" then
    return aggregate_cluster(res)
  end

  return res
end


function _M:insert_stats(data, node_id)
  local at, hit, miss, plat_min, plat_max, query, res, err
  local now = time()
  local minute = cassandra.timestamp(self:get_minute(now))
  local hour = cassandra.timestamp(self:get_hour(now))

  -- passing node_id is for ease of testing
  if node_id then
    node_id = cassandra.uuid(node_id)
  else
    node_id = self.node_id
  end

  -- accumulator for minutes data
  local minute_acc = {
    l2_hit   = 0,
    l2_miss  = 0,
    plat_min = cassandra.null,
    plat_max = cassandra.null,
  }

  -- iterate over seconds data
  for _, row in ipairs(data) do
    at, hit, miss, plat_min, plat_max = unpack(row)

    plat_min = plat_min or cassandra.null
    plat_max = plat_max or cassandra.null

    -- add current second data to minute accumulator
    aggregate_stats(minute_acc, hit, miss, plat_min, plat_max)

    query = fmt(INSERT_STATS, 'vitals_stats_seconds', 'minute', self.seconds_ttl)

    -- insert seconds row
    res, err = self.cluster:execute(query, {
      node_id,
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
    node_id,
    hour,
    minute,
    minute_acc.l2_hit,
    minute_acc.l2_miss,
    minute_acc.plat_min,
    minute_acc.plat_max
  }, QUERY_OPTIONS)

  if not res then
    return nil, "could not insert stats. query: " .. query .. " error: " .. err
  end

  -- finally, update last_reported in vitals_node_meta
  res, err = self.cluster:execute(UPDATE_NODE, {
    cassandra.timestamp(now * 1000),
    node_id,
  }, QUERY_OPTIONS)

  if not res then
    return nil, "could not update node last_reported: " .. UPDATE_NODE .. " error: " .. err
  end

  return true
end


function _M:delete_stats(cutoff_times)
  -- this is a no-op for Cassandra
  return 0
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


--[[
  data: a 2D-array of [
    [consumer_id, timestamp, duration, count]
  ]
]]
function _M:insert_consumer_stats(data, node_id)
  local res, err, count, at, duration, consumer_id

  if node_id then
    node_id = cassandra.uuid(node_id)
  else
    node_id = self.node_id
  end

  for _, row in ipairs(data) do
    consumer_id, at, duration, count = unpack(row)

    local count_converted = cassandra.counter(count)
    local now_converted = cassandra.timestamp(at * 1000)
    local minute = cassandra.timestamp(self:get_minute(at))
    local consumer_id_converted = cassandra.uuid(consumer_id)

    res, err = self.cluster:execute(INSERT_CONSUMER_STATS, {
      count_converted,
      now_converted,
      duration,
      consumer_id_converted,
      node_id,
    }, COUNTER_QUERY_OPTIONS)


    if not res then
      return nil, "could not insert seconds data. error: " .. err
    end

    res, err = self.cluster:execute(INSERT_CONSUMER_STATS, {
      count_converted,
      minute,
      60,
      consumer_id_converted,
      node_id,
    }, COUNTER_QUERY_OPTIONS)

    if not res then
      return nil, "could not insert minutes data. error: " .. err
    end
  end

  return true
end


function _M:delete_consumer_stats(consumers, cutoff_times)
end


function _M:node_exists(node_id)
  local res, err = self.cluster:execute(SELECT_NODE, {
    cassandra.uuid(node_id),
  }, QUERY_OPTIONS)

  if err then
    return nil, err
  end

  return res[1] ~= nil
end

return _M
