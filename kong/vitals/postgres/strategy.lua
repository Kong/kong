local table_rotater_module = require "kong.vitals.postgres.table_rotater"
local fmt                  = string.format
local unpack               = unpack
local tostring             = tostring
local time                 = ngx.time
local log                  = ngx.log
local WARN                 = ngx.WARN
local DEBUG                = ngx.DEBUG
local math_min             = math.min
local math_max             = math.max

local _M = {}
local mt = { __index = _M }

local _log_prefix = "[vitals-strategy] "

local INSERT_STATS = [[
  insert into %s (at, node_id, l2_hit, l2_miss, plat_min, plat_max, ulat_min, ulat_max, requests)
  values (%d, '%s', %d, %d, %s, %s, %s, %s, %d)
  on conflict (node_id, at) do update set
    l2_hit = %s.l2_hit + excluded.l2_hit,
    l2_miss = %s.l2_miss + excluded.l2_miss,
    plat_min = least(%s.plat_min, excluded.plat_min),
    plat_max = greatest(%s.plat_max, excluded.plat_max),
    ulat_min = least(%s.ulat_min, excluded.ulat_min),
    ulat_max = greatest(%s.ulat_max, excluded.ulat_max),
    requests = %s.requests + excluded.requests
]]

local INSERT_CONSUMER_STATS = [[
  insert into vitals_consumers(consumer_id, node_id, at, duration, count)
  values('%s', '%s', to_timestamp(%d) at time zone 'UTC', %d, %d)
  on conflict(consumer_id, node_id, at, duration) do
  update set count = vitals_consumers.count + excluded.count
]]

local UPDATE_NODE_META = "update vitals_node_meta set last_report = now() where node_id = '%s'"

local DELETE_STATS = "delete from %s where at < %d"

local DELETE_CONSUMER_STATS = [[
  delete from vitals_consumers where consumer_id = '{%s}'
  and ((duration = %d and at < to_timestamp(%d) at time zone 'UTC')
  or (duration = %d and at < to_timestamp(%d) at time zone 'UTC'))
]]

function _M.dynamic_table_names(dao)
  local table_names = {}

  -- capture the dynamically-created tables
  local query = [[select table_name from information_schema.tables
      where table_schema = 'public' and table_name like 'vitals_stats_seconds_%']]

  local result, err = dao.db:query(query)
  if not result then
    -- just return what we've got, don't halt processing
    log(WARN, _log_prefix, err)
    return table_names
  end

  for i, v in ipairs(result) do
    table_names[i] = v.table_name
  end

  return table_names
end

function _M.new(dao_factory, opts)
  if opts == nil then
    opts = {}
  end

  local table_rotater = table_rotater_module.new(
    {
      db = dao_factory.db,
      rotation_interval = opts.ttl_seconds or 3600,
    }
  )

  local self = {
    db = dao_factory.db,
    table_rotater = table_rotater,
    node_id = nil,
    hostname = nil,
  }

  return setmetatable(self, mt)
end


function _M:init(node_id, hostname)
  if not node_id then
    return nil, "node_id is required"
  end

  local ok, err = self.table_rotater:init()

  if not ok then
    return nil, "failed to init table rotator: " .. err
  end

  self.node_id = node_id
  self.hostname = hostname

  local ok, err = self:insert_node_meta()
  if not ok then
    return nil, "failed to record node info: " .. err
  end

  return true
end


--[[
  Note: all parameters are validated in vitals:get_stats()

  query_type: "seconds" or "minutes"
  level: "node" to get stats for all nodes or "cluster"
  node_id: if given, selects stats just for that node
 ]]
function _M:select_stats(query_type, level, node_id)
  local query, res, err

  -- for constructing dynamic SQL
  local select, from_t1, where, from_t2
  local group = ""

  -- construct the SELECT clause
  if level == "node" then
    select = "SELECT * "
  else
    -- must be cluster
    select = [[
      SELECT at,
             'cluster' as node_id,
             sum(l2_hit) as l2_hit,
             sum(l2_miss) as l2_miss,
             min(plat_min) as plat_min,
             max(plat_max) as plat_max,
             min(ulat_min) as ulat_min,
             max(ulat_max) as ulat_max,
             sum(requests) as requests
      ]]
    group = " GROUP BY at "
  end

  -- construct the FROM clause
  if query_type == "seconds" then
    local table_names, err = self:table_names_for_select()

    if err then
      return nil, err
    end

    from_t1 = " FROM " .. table_names[1]

    if table_names[2] then
      from_t2 = " FROM " .. table_names[2]
    end
  else
    -- must be minutes
    from_t1 = " FROM vitals_stats_minutes "
  end

  -- construct the WHERE clause
  where = " WHERE 1=1 "
  if level == "node" then
    if node_id then
      where = where .. " AND node_id = '{" .. node_id .. "}' "
    end
  end

  -- put it all together
  query = select .. from_t1 .. where .. group

  if from_t2 then
    query = query .. " UNION " .. select .. from_t2 .. where .. group
  end

  query = query .. " ORDER BY at"

  -- BOOM
  res, err = self.db:query(query)
  if not res then
    return nil, "could not select stats. query: " .. query .. " error: " .. err
  end

  return res
end


--[[
  constructs an insert statement for each row in data. If there's already a row
  with this timestamp, aggregates appropriately per stat type

  data: a 2D-array of [
    [
      timestamp, l2_hits, l2_misses, proxy_latency_min, proxy_latency_max,
      upstream_latency_min, upstream_latency_max, requests
    ],
    ...
  ]
]]
function _M:insert_stats(data, node_id)
  local at, hit, miss, plat_min, plat_max, query, res, err, ulat_min, ulat_max, requests
  local table_name = self:current_table_name()

  -- node_id is an optional argument to simplify testing
  node_id = node_id or self.node_id

  -- as we loop over our seconds, we'll calculate the minutes data to insert
  local mdata = {} -- array of data to insert
  local midx  = {} -- table of timestamp to array index
  local mnext = 1  -- next index in mdata

  for _, row in ipairs(data) do
    at, hit, miss, plat_min, plat_max, ulat_min, ulat_max, requests = unpack(row)

    local mat = self:get_minute(at)
    local i   = midx[mat]
    if i then
      mdata[i][2] = mdata[i][2] + hit
      mdata[i][3] = mdata[i][3] + miss
      mdata[i][4] = math_min(mdata[i][4], plat_min or 0xFFFFFFFF)
      mdata[i][5] = math_max(mdata[i][5], plat_max or -1)
      mdata[i][6] = math_min(mdata[i][6], ulat_min or 0xFFFFFFFF)
      mdata[i][7] = math_max(mdata[i][7], ulat_max or -1)
      mdata[i][8] = mdata[i][8] + requests
    else
      mdata[mnext] = {
        mat,
        hit,
        miss,
        plat_min or 0xFFFFFFFF,
        plat_max or -1,
        ulat_min or 0xFFFFFFFF,
        ulat_max or -1,
        requests,
      }
      midx[mat] = mnext
      mnext  = mnext + 1
    end

    plat_min = plat_min or "null"
    plat_max = plat_max or "null"
    ulat_min = ulat_min or "null"
    ulat_max = ulat_max or "null"

    query = fmt(INSERT_STATS, table_name, at, node_id, hit, miss, plat_min,
                plat_max, ulat_min, ulat_max, requests, table_name, table_name,
                table_name, table_name, table_name, table_name, table_name)
    res, err = self.db:query(query)

    if not res then
      log(WARN, _log_prefix, "failed to insert seconds: ", err)
      log(DEBUG, _log_prefix, "failed query: ", query)
    end
  end

  -- insert minutes data
  local tname = "vitals_stats_minutes"
  for _, row in ipairs(mdata) do
    at, hit, miss, plat_min, plat_max, ulat_min, ulat_max, requests = unpack(row)

    -- replace sentinels
    if plat_min == 0xFFFFFFFF then
      plat_min = "null"
      plat_max = "null"
    end
    if ulat_min == 0xFFFFFFFF then
      ulat_min = "null"
      ulat_max = "null"
    end

    query = fmt(INSERT_STATS, tname, at, node_id,
                hit, miss, plat_min, plat_max, ulat_min, ulat_max, requests,
                tname, tname, tname, tname, tname, tname, tname)
    res, err = self.db:query(query)

    if not res then
      log(WARN, _log_prefix, "failed to insert minutes: ", err)
      log(DEBUG, _log_prefix, "failed query: ", query)
    end
  end

  local ok, err = self:update_node_meta(node_id)
  if not ok then
    return nil, "could not update metadata. query: " .. query .. " error: " .. err
  end

  return true
end


function _M:delete_stats(expiries)
  if not expiries then
    return nil, "cutoff_times is required"
  end

  -- eventually will also support 'hours' and larger
  if type(expiries.minutes) ~= "number" then
    return nil, "cutoff_times.minutes must be a number"
  end

  -- for now, only aggregation supported is minutes
  local cutoff_time = time() - expiries.minutes
  local q = fmt(DELETE_STATS, "vitals_stats_minutes", cutoff_time)

  local res, err = self.db:query(q)

  if err then
    return nil, err
  end

  return res.affected_rows
end


function _M:insert_node_meta()
  -- we only perform this query once, so concatenation here is okay
  local q = "insert into vitals_node_meta " ..
            "(node_id, hostname, first_report, last_report) " ..
            "values('{%s}', '%s', now(), now()) on conflict(node_id) do nothing"

  local query = fmt(q, self.node_id, self.hostname)

  local ok, err = self.db:query(query)
  if not ok then
    return nil, "could not insert metadata. query: " .. query .. " error " .. err
  end

  return true
end


function _M:update_node_meta(node_id)
  node_id = node_id or self.node_id
  local query = fmt(UPDATE_NODE_META, node_id)

  local ok, err = self.db:query(query)
  if not ok then
    return nil, "could not update metadata. query: " .. query  .. " error " .. err
  end

  return true
end


--[[
  takes an options table that contains the following:
  - consumer_id that must be a valid uuid
  - duration that must be one of (1, 60)
  - at - in epoch format
  - end_at - in epoch format
  - level - "node" or "cluster"

  at must be valid for the given duration

  if node_id is provided, it must be a valid uuid

  all arguments are validated in the vitals module

  returns an array of
  { node_id, at, count }
  where node_id is either the UUID of the requested node,
  or "cluster" when requesting cluster-level data
]]
function _M:select_consumer_stats(opts)
  local level    = opts.level
  local node_id  = opts.node_id
  local cons_id  = opts.consumer_id
  local duration = opts.duration

  local query, res, err

  -- for constructing dynamic SQL
  local select, from, where
  local group = ""

  -- construct the SELECT clause
  if level == "node" then
    select = [[
      SELECT node_id,
             extract('epoch' from at) as at,
             count
      ]]
  else
    -- must be cluster
    select = [[
      SELECT 'cluster' as node_id,
             extract('epoch' from at) as at,
             sum(count) as count
      ]]
    group = " GROUP BY at "
  end

  -- construct the FROM clause
  from = " FROM vitals_consumers "

  -- construct the WHERE clause
  local where_clause = " WHERE consumer_id = '{%s}' AND duration = %d "

  where = fmt(where_clause, cons_id, duration)

  if level == "node" and node_id then
    where = where .. " AND node_id = '{" .. node_id .. "}' "
  end

  -- put it all together
  query = select .. from .. where .. group .. " ORDER BY at"

  res, err = self.db:query(query)
  if not res then
    return nil, "could not select stats. query: " .. query .. " error: " .. err
  end

  return res
end


--[[
  data: a 2D-array of [
    [consumer_id, timestamp, duration, count]
  ]
]]
function _M:insert_consumer_stats(data, node_id)
  local consumer_id, at, duration, count
  local query, last_err
  local row_count  = 0
  local fail_count = 0

  node_id = node_id or self.node_id

  for _, row in ipairs(data) do
    row_count = row_count + 2 -- one for seconds, one for minutes

    consumer_id, at, duration, count = unpack(row)

    query = fmt(INSERT_CONSUMER_STATS, consumer_id, node_id, at,
                duration, count)

    local res, err = self.db:query(query)
    if not res then
      fail_count = fail_count + 1
      last_err   = tostring(err)
    end

    -- naive approach - update minutes in-line
    local mat = self:get_minute(at)
    query = fmt(INSERT_CONSUMER_STATS, consumer_id, node_id, mat,
                60, count)

    local res, err = self.db:query(query)
    if not res then
      fail_count = fail_count + 1
      last_err   = tostring(err)
    end
  end

  if fail_count > 0 then
    return nil, "failed to insert " .. tostring(fail_count) .. " of " ..
        tostring(row_count) .. " consumer stats. last err: " .. last_err
  end

  return true
end


--[[
--deletes data for the given list of consumers
  cutoff_times: a table of timeframes to delete; e.g.
  {
    minutes = 1510759610 <- delete minutes data before this ts
    seconds = 1510846084 <- delete seconds data before this ts
  }

  entries for minutes and seconds are both required
]]
function _M:delete_consumer_stats(consumers, cutoff_times)
  if not next(consumers) then
    return 0
  end

  local query, last_err
  local fail_count = 0
  local cons_count = 0
  local row_count  = 0

  for consumer, _ in pairs(consumers) do
    cons_count = cons_count + 1

    query = fmt(DELETE_CONSUMER_STATS, consumer, 1, cutoff_times.seconds,
        60, cutoff_times.minutes)

    local res, err = self.db:query(query)

    if res then
      row_count = row_count + res.affected_rows
    else
      fail_count = fail_count + 1
      last_err   = err
    end
  end

  -- total failure
  if fail_count == cons_count then
    return nil, "failed to delete consumer stats. last err: " .. last_err
  end

  -- not a complete failure
  if fail_count > 0 then
    return cons_count - fail_count, "failed to delete " .. tostring(fail_count) ..
        "stats for " .. tostring(row_count) .. " consumers. last err: " .. last_err
  end

  return row_count
end


function _M:get_minute(second)
  return second - (second % 60)
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


function _M:check_node(node_id)
  local SELECT_NODE = [[
    select node_id from vitals_node_meta where node_id = '%s'
  ]]

  query = fmt(SELECT_NODE, node_id)

  res, err = self.db:query(query)

  if not res then
    return nil, "could not select node_id. query: " .. query .. " error: " .. err
  end

  return res
end

return _M
