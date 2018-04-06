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
  INSERT INTO %s (at, node_id, l2_hit, l2_miss, plat_min, plat_max, ulat_min,
    ulat_max, requests, plat_count, plat_total, ulat_count, ulat_total)
  VALUES (%d, '%s', %d, %d, %s, %s, %s, %s, %d, %d, %d, %d, %d)
  ON CONFLICT (node_id, at) DO UPDATE SET
    l2_hit = %s.l2_hit + excluded.l2_hit,
    l2_miss = %s.l2_miss + excluded.l2_miss,
    plat_min = least(%s.plat_min, excluded.plat_min),
    plat_max = greatest(%s.plat_max, excluded.plat_max),
    ulat_min = least(%s.ulat_min, excluded.ulat_min),
    ulat_max = greatest(%s.ulat_max, excluded.ulat_max),
    requests = %s.requests + excluded.requests,
    plat_count = %s.plat_count + excluded.plat_count,
    plat_total = %s.plat_total + excluded.plat_total,
    ulat_count = %s.ulat_count + excluded.ulat_count,
    ulat_total = %s.ulat_total + excluded.ulat_total
]]

local SELECT_STATS_FOR_PHONE_HOME = [[
  SELECT SUM(l2_hit) AS "v.cdht",
  SUM(l2_miss) AS "v.cdmt",
  MIN(plat_min) AS "v.lprn",
  MAX(plat_max) AS "v.lprx",
  MIN(ulat_min) AS "v.lun",
  MAX(ulat_max) AS "v.lux",
  SUM(plat_count) AS plat_count,
  SUM(plat_total) AS plat_total,
  SUM(ulat_count) AS ulat_count,
  SUM(ulat_total) AS ulat_total
  FROM vitals_stats_minutes WHERE at >= %d AND node_id = '%s'
]]

local SELECT_NODES_FOR_PHONE_HOME = [[
  SELECT COUNT(DISTINCT node_id) AS "v.nt" FROM vitals_stats_minutes WHERE at >= %d
]]

local INSERT_CONSUMER_STATS = [[
  INSERT INTO vitals_consumers(consumer_id, node_id, at, duration, count)
  VALUES('%s', '%s', to_timestamp(%d) at time zone 'UTC', %d, %d)
  ON CONFLICT(consumer_id, node_id, at, duration) DO
  UPDATE SET COUNT = vitals_consumers.count + excluded.count
]]

local UPDATE_NODE_META = "UPDATE vitals_node_meta SET last_report = now() WHERE node_id = '%s'"

local DELETE_STATS = "DELETE FROM %s WHERE at < %d"

local DELETE_CONSUMER_STATS = [[
  DELETE FROM vitals_consumers WHERE consumer_id = '{%s}'
  AND ((duration = %d AND at < to_timestamp(%d) AT TIME ZONE 'UTC')
  OR (duration = %d AND at < to_timestamp(%d) AT TIME ZONE 'UTC'))
]]

local SELECT_NODE = "SELECT node_id FROM vitals_node_meta WHERE node_id = '%s'"

local SELECT_NODE_META = [[
  SELECT node_id, hostname FROM vitals_node_meta WHERE node_id IN ('%s')
]]

local INSERT_CODE_CLASSES_CLUSTER = [[
  INSERT INTO vitals_code_classes_by_cluster(code_class, at, duration, count)
  VALUES(%d, to_timestamp(%d) at time zone 'UTC', %d, %d)
  ON CONFLICT(code_class, at, duration) DO
  UPDATE SET COUNT = vitals_code_classes_by_cluster.count + excluded.count
]]

local SELECT_CODE_CLASSES_CLUSTER = [[
  SELECT 'cluster' as node_id, code_class, extract('epoch' from at) as at, count
    FROM vitals_code_classes_by_cluster
   WHERE duration = %d AND at >= to_timestamp(%d)
]]

local DELETE_CODE_CLASSES_CLUSTER = [[
  DELETE FROM vitals_code_classes_by_cluster
  WHERE ((duration = %d AND at < to_timestamp(%d) AT TIME ZONE 'UTC')
  OR (duration = %d AND at < to_timestamp(%d) AT TIME ZONE 'UTC'))
]]

local INSERT_CODES = [[
  INSERT INTO %s(%s, code, at, duration, count)
  VALUES('%s', '%s', to_timestamp(%d) at time zone 'UTC', %d, %d)
  ON CONFLICT(%s, code, at, duration) DO
  UPDATE SET COUNT = %s.count + excluded.count
]]

local SELECT_CODES_SERVICE = [[
  SELECT service_id, code, extract('epoch' from at) as at, count
    FROM vitals_codes_by_service
   WHERE service_id = '%s' AND duration = %d AND at >= to_timestamp(%d)
]]

local DELETE_CODES = [[
  DELETE FROM %s
  WHERE ((duration = %d AND at < to_timestamp(%d) AT TIME ZONE 'UTC')
  OR (duration = %d AND at < to_timestamp(%d) AT TIME ZONE 'UTC'))
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
    ttl_seconds = opts.ttl_seconds or 3600,
    ttl_minutes = opts.ttl_minutes or 90000,
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
  start_at: first timestamp, inclusive
  end_before: last timestamp, exclusive
 ]]
function _M:select_stats(query_type, level, node_id, start_at, end_before)
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
             sum(requests) as requests,
             sum(plat_count) as plat_count,
             sum(plat_total) as plat_total,
             sum(ulat_count) as ulat_count,
             sum(ulat_total) as ulat_total
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

  if start_at then
    where = where .. " AND at >= " .. start_at
  end

  if end_before then
    where = where .. " AND at < " .. end_before
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


function _M:select_phone_home()
  local res, err = self.db:query(fmt(SELECT_STATS_FOR_PHONE_HOME, time() - 3600, self.node_id))

  if not res then
    return nil, "could not select stats: " .. err
  end

  -- the only time res[1].plat_count would be nil is when phone_home is
  -- invoked before any minutes data is written. Oh, and in unit tests.
  if res[1].plat_count and res[1].plat_count > 0 then
    res[1]["v.lpra"] = math.floor(res[1].plat_total / res[1].plat_count + 0.5)
  end

  if res[1].ulat_count and res[1].ulat_count > 0 then
    res[1]["v.lua"] = math.floor(res[1].ulat_total / res[1].ulat_count + 0.5)
  end

  for _, v in ipairs({ "plat_count", "plat_total", "ulat_count", "ulat_total" }) do
    res[1][v] = nil
  end

  local nodes, err = self.db:query(fmt(SELECT_NODES_FOR_PHONE_HOME, time() - 3600))
  if not res then
    return nil, "could not count nodes: " .. err
  end
  res[1]["v.nt"] = nodes[1]["v.nt"]

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
  local at, hit, miss, plat_min, plat_max, query, res, err, ulat_min, ulat_max,
        requests, plat_count, plat_total, ulat_count, ulat_total
  local tname = self:current_table_name()

  -- node_id is an optional argument to simplify testing
  node_id = node_id or self.node_id

  -- as we loop over our seconds, we'll calculate the minutes data to insert
  local mdata = {} -- array of data to insert
  local midx  = {} -- table of timestamp to array index
  local mnext = 1  -- next index in mdata

  for _, row in ipairs(data) do
    at, hit, miss, plat_min, plat_max, ulat_min, ulat_max, requests,
      plat_count, plat_total, ulat_count, ulat_total = unpack(row)

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
      mdata[i][9] = mdata[i][9] + plat_count
      mdata[i][10] = mdata[i][10] + plat_total
      mdata[i][11] = mdata[i][11] + ulat_count
      mdata[i][12] = mdata[i][12] + ulat_total
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
        plat_count,
        plat_total,
        ulat_count,
        ulat_total
      }
      midx[mat] = mnext
      mnext  = mnext + 1
    end

    plat_min = plat_min or "null"
    plat_max = plat_max or "null"
    ulat_min = ulat_min or "null"
    ulat_max = ulat_max or "null"

    query = fmt(INSERT_STATS, tname, at, node_id, hit, miss, plat_min,
                plat_max, ulat_min, ulat_max, requests, plat_count, plat_total,
                ulat_count, ulat_total, tname, tname, tname, tname, tname, tname,
                tname, tname, tname, tname, tname)

    res, err = self.db:query(query)

    if not res then
      log(WARN, _log_prefix, "failed to insert seconds: ", err)
      log(DEBUG, _log_prefix, "failed query: ", query)
    end
  end

  -- insert minutes data
  local tname = "vitals_stats_minutes"
  for _, row in ipairs(mdata) do
    at, hit, miss, plat_min, plat_max, ulat_min, ulat_max, requests,
    plat_count, plat_total, ulat_count, ulat_total = unpack(row)

    -- replace sentinels
    if plat_min == 0xFFFFFFFF then
      plat_min = "null"
      plat_max = "null"
    end
    if ulat_min == 0xFFFFFFFF then
      ulat_min = "null"
      ulat_max = "null"
    end

    query = fmt(INSERT_STATS, tname, at, node_id, hit, miss, plat_min,
      plat_max, ulat_min, ulat_max, requests, plat_count, plat_total,
      ulat_count, ulat_total, tname, tname, tname, tname, tname, tname,
      tname, tname, tname, tname, tname)

    res, err = self.db:query(query)

    if not res then
      log(WARN, _log_prefix, "failed to insert minutes: ", err)
      log(DEBUG, _log_prefix, "failed query: ", query)
    end
  end

  local ok, err = self:update_node_meta(node_id)
  if not ok then
    return nil, "could not update metadata. error: " .. err
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


function _M:select_node_meta(node_ids)
  if not node_ids or not node_ids[1] then
    return {}
  end

  -- format the node ids for query interpolation
  local node_ids_str = table.concat(node_ids, "', '")

  local query = fmt(SELECT_NODE_META, node_ids_str)

  local res, err = self.db:query(query)

  if err then
    return nil, "could not select nodes. query: " .. query .. " error " .. err
  end

  return res
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


function _M:insert_status_code_classes(data)
  local res, err, count, at, duration, code_class, query

  for _, row in ipairs(data) do
    code_class, at, duration, count = unpack(row)

    query = fmt(INSERT_CODE_CLASSES_CLUSTER, code_class, at,
                duration, count)

    res, err = self.db:query(query)

    if not res then
      return nil, "could not insert status code counters. error: " .. err
    end
  end

  return true
end


function _M:select_status_code_classes(opts)
  local duration = opts.duration

  if duration ~= 1 and duration ~= 60 then
    return nil, "duration must be 1 or 60"
  end

  local cutoff_time

  if duration == 1 then
    cutoff_time = time() - self.ttl_seconds
  else
    cutoff_time = time() - self.ttl_minutes
  end

  local query = fmt(SELECT_CODE_CLASSES_CLUSTER, opts.duration, cutoff_time)
  local res, err = self.db:query(query)
  if err then
    return nil, "failed to select code classes. err: " .. err
  end

  return res
end


function _M:delete_status_code_classes(cutoff_times)
  if type(cutoff_times) ~= "table" then
    return nil, "cutoff_times must be a table"
  end

  if type(cutoff_times.seconds) ~= "number" then
    return nil, "cutoff seconds must be a number"
  end

  if type(cutoff_times.minutes) ~= "number" then
    return nil, "cutoff minutes must be a number"
  end

  local query = fmt(DELETE_CODE_CLASSES_CLUSTER, 1, cutoff_times.seconds,
                    60, cutoff_times.minutes)

  local res, err = self.db:query(query)

  if err then
    return nil, "failed to delete code_classes. err: " .. err
  end

  return res.affected_rows
end


function _M:insert_status_codes(data, opts)
  if type(opts) ~= "table" then
    return nil, "opts must be a table"
  end

  local entity_type = opts.entity_type

  if entity_type ~= "service" and entity_type ~= "route" then
    return nil, "opts.entity_type must be 'service' or 'route'"
  end

  local res, err, entity_id, at, duration, code, count, query
  local table, column

  for _, v in ipairs(data) do
    -- TODO: obviate the need for this check
    if entity_type == "service" then
      entity_id, code, at, duration, count = unpack(v)
      table = "vitals_codes_by_service"
      column = "service_id"
    else
      entity_id, _, code, at, duration, count = unpack(v)
      table = "vitals_codes_by_route"
      column = "route_id"
    end

    query = fmt(INSERT_CODES,
                table,
                column,
                entity_id,
                code,
                at,
                duration,
                count,
                column,
                table)

    res, err = self.db:query(query)

    if not res then
      return nil, "could not insert status code counters. error: " .. err
    end
  end

  if opts.prune then
    local now = time()

    self:delete_status_codes({
      entity_type = entity_type,
      seconds = now - self.ttl_seconds,
      minutes = now - self.ttl_minutes,
    })
  end

  return true
end


function _M:insert_status_codes_by_service(data)
  return self:insert_status_codes(data, {
    entity_type = "service",
    prune = true,
  })
end


function _M:select_status_codes_by_service(opts)
  local duration = opts.duration

  if duration ~= 1 and duration ~= 60 then
    return nil, "duration must be 1 or 60"
  end

  local cutoff_time

  if duration == 1 then
    cutoff_time = time() - self.ttl_seconds
  else
    cutoff_time = time() - self.ttl_minutes
  end

  local query = fmt(SELECT_CODES_SERVICE, opts.service_id, opts.duration, cutoff_time)

  local res, err = self.db:query(query)

  if err then
    return nil, "failed to select codes. err: " .. err
  end

  return res
end


function _M:delete_status_codes(opts)
  if type(opts) ~= "table" then
    return nil, "opts must be a table"
  end

  if opts.entity_type ~= "service" and opts.entity_type ~= "route" then
    return nil, "opts.entity_type must be 'service' or 'route'"
  end

  if type(opts.seconds) ~= "number" then
    return nil, "opts.seconds must be a number"
  end

  if type(opts.minutes) ~= "number" then
    return nil, "opts.minutes must be a number"
  end

  -- TODO: this logic is written with the assumption that we store
  -- codes in separate tables
  local table_name
  if opts.entity_type == "service" then
    table_name = "vitals_codes_by_service"
  else
    table_name = "vitals_codes_by_route"
  end

  local query = fmt(DELETE_CODES, table_name, 1, opts.seconds,
                    60, opts.minutes)

  local res, err = self.db:query(query)

  if err then
    return nil, "failed to delete codes. err: " .. err
  end

  return res.affected_rows
end


function _M:get_minute(second)
  return second - (second % 60)
end


function _M:current_table_name()
  return self.table_rotater:current_table_name()
end


function _M:table_names_for_select()
  return self.table_rotater:table_names_for_select()
end


function _M:node_exists(node_id)
  local query = fmt(SELECT_NODE, node_id)

  local res, err = self.db:query(query)

  if err then
    return nil, err
  end

  return res[1] ~= nil
end

return _M
