local table_rotater_module = require "kong.vitals.postgres.table_rotater"
local fmt                  = string.format
local unpack               = unpack
local tostring             = tostring
local match                = string.match
local time                 = ngx.time
local log                  = ngx.log
local WARN                 = ngx.WARN
local DEBUG                = ngx.DEBUG
local INFO                 = ngx.INFO
local math_min             = math.min
local math_max             = math.max
local timer_at             = ngx.timer.at

local delete_handler

local _M = {}
local mt = { __index = _M }

local _log_prefix = "[vitals-strategy] "
local DELETE_LOCK_KEY = "postgres:delete_lock"

local ACQUIRE_LOCK_STATUS_CODES_DELETE = [[
  UPDATE vitals_locks SET expiry = to_timestamp(%d) at time zone 'UTC'
  WHERE key = 'delete_status_codes'
  AND ((expiry <= to_timestamp(%d) AT TIME ZONE 'UTC')
  OR (expiry IS NULL))
]]

local RELEASE_LOCK_STATUS_CODES_DELETE = [[
  UPDATE vitals_locks SET expiry = NULL WHERE key = 'delete_status_codes'
]]

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

local UPDATE_NODE_META = "UPDATE vitals_node_meta SET last_report = now() WHERE node_id = '%s'"

local DELETE_STATS = "DELETE FROM %s WHERE at < %d"

local SELECT_NODE = "SELECT node_id FROM vitals_node_meta WHERE node_id = '%s'"

local SELECT_NODE_META = [[
  SELECT node_id, hostname FROM vitals_node_meta WHERE node_id IN ('%s')
]]

local INSERT_CODE_CLASSES_CLUSTER = [[
  INSERT INTO vitals_code_classes_by_cluster(code_class, at, duration, count)
  VALUES %s
  ON CONFLICT(code_class, at, duration) DO
  UPDATE SET COUNT = vitals_code_classes_by_cluster.count + excluded.count
]]

local SELECT_CODE_CLASSES_CLUSTER = [[
  SELECT 'cluster' as node_id, code_class, extract('epoch' from at) as at, count
    FROM vitals_code_classes_by_cluster
   WHERE duration = %d AND at >= to_timestamp(%d)
]]

local INSERT_CODE_CLASSES_WORKSPACE = [[
  INSERT INTO vitals_code_classes_by_workspace(workspace_id, code_class, at, duration, count)
  VALUES %s
  ON CONFLICT(workspace_id, code_class, at, duration) DO
  UPDATE SET COUNT = vitals_code_classes_by_workspace.count + excluded.count
]]

local SELECT_CODE_CLASSES_WORKSPACE = [[
  SELECT 'cluster' as node_id, code_class, extract('epoch' from at) as at, count
    FROM vitals_code_classes_by_workspace
   WHERE workspace_id = '%s'
     AND duration = %d AND at >= to_timestamp(%d)
]]

local INSERT_CODES_BY_ROUTE = [[
  INSERT INTO vitals_codes_by_route(route_id, service_id, code, at, duration, count)
  VALUES %s
  ON CONFLICT(route_id, code, at, duration) DO
  UPDATE SET COUNT = vitals_codes_by_route.count + excluded.count
]]

local INSERT_CODES_BY_CONSUMER_AND_ROUTE = [[
  INSERT INTO vitals_codes_by_consumer_route(consumer_id, route_id, service_id, code, at, duration, count)
  VALUES %s
  ON CONFLICT(consumer_id, route_id, code, at, duration) DO
  UPDATE SET COUNT = vitals_codes_by_consumer_route.count + excluded.count
]]

local SELECT_CODES_SERVICE = [[
SELECT service_id, code, extract('epoch' from at) as at, sum(count) as count
  FROM vitals_codes_by_route
 WHERE service_id = '%s' AND duration = %d AND at >= to_timestamp(%d)
 GROUP BY service_id, code, at
]]

local SELECT_CODES_ROUTE = [[
  SELECT route_id, code, extract('epoch' from at) as at, count
    FROM vitals_codes_by_route
   WHERE route_id = '%s' AND duration = %d AND at >= to_timestamp(%d)
]]

local SELECT_CODES_CONSUMER = [[
  SELECT consumer_id, code, extract('epoch' from at) as at, sum(count) as count
    FROM vitals_codes_by_consumer_route
   WHERE consumer_id = '%s' AND duration = %d AND at >= to_timestamp(%d)
   GROUP BY consumer_id, code, at
]]

local SELECT_CODES_CONSUMER_ROUTE = [[
  SELECT consumer_id, route_id, code, extract('epoch' from at) as at, sum(count) as count
    FROM vitals_codes_by_consumer_route
   WHERE consumer_id = '%s' AND duration = %d AND at >= to_timestamp(%d)
   GROUP BY consumer_id, route_id, code, at
]]

local SELECT_REQUESTS_CONSUMER = [[
  SELECT 'cluster' as node_id, extract('epoch' from at) as at, sum(count) as count
    FROM vitals_codes_by_consumer_route
   WHERE consumer_id = '%s' AND duration = %d AND at >= to_timestamp(%d)
   GROUP BY at
]]

local DELETE_CODES = [[
  DELETE FROM %s
   WHERE (duration = %d AND at < to_timestamp(%d) AT TIME ZONE 'UTC')
      OR (duration = %d AND at < to_timestamp(%d) AT TIME ZONE 'UTC')
]]

local STATUS_CODE_QUERIES = {
  SELECT = {
    cluster = SELECT_CODE_CLASSES_CLUSTER,
    workspace = SELECT_CODE_CLASSES_WORKSPACE,
    consumer_route = SELECT_CODES_CONSUMER_ROUTE,
    consumer = SELECT_CODES_CONSUMER,
    service = SELECT_CODES_SERVICE,
    route = SELECT_CODES_ROUTE,
  },
  INSERT = {
    cluster = INSERT_CODE_CLASSES_CLUSTER,
    workspace = INSERT_CODE_CLASSES_WORKSPACE,
    consumer_route = INSERT_CODES_BY_CONSUMER_AND_ROUTE,
    route = INSERT_CODES_BY_ROUTE,
  },
  DELETE = {
    cluster = "vitals_code_classes_by_cluster",
    workspace = "vitals_code_classes_by_workspace",
    consumer_route = "vitals_codes_by_consumer_route",
    route = "vitals_codes_by_route",
  }
}

function _M.dynamic_table_names(db)
  local table_names = {}

  -- capture the dynamically-created tables
  local query = [[select table_name from information_schema.tables
      where table_schema = 'public' and table_name like 'vitals_stats_seconds_%']]

  local result, err = db.connector:query(query)
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


function _M.new(db, opts)
  if opts == nil then
    opts = {}
  end

  local table_rotater = table_rotater_module.new(
    {
      connector = db.connector,
      rotation_interval = opts.ttl_seconds or 3600,
    }
  )

  local self = {
    list_cache = ngx.shared.kong_vitals_lists,
    delete_interval = opts.delete_interval or 30,
    connector = db.connector,
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

  -- delete timer
  local when = self.delete_interval
  log(INFO, _log_prefix, "starting initial postgres delete timer in ", when, " seconds")

  local _, err = timer_at(when, delete_handler, self)
  if err then
    return nil, "failed to start initial postgres delete timer: " .. err
  end

  return true
end


delete_handler = function(premature, self)
  if premature then
    return
  end

  local when = self.delete_interval
  local now = ngx.now()

  -- Attempt to get a worker-level and cluster-wide delete lock
  if self:acquire_lock_status_codes_delete(now, when) then
    log(DEBUG, _log_prefix, "recurring postgres delete has started")

    -- iterate over status code entities and delete expired stats
    for _, entity_type in ipairs({ "consumer_route", "route", "workspace", "cluster" }) do
      local _, err = self:delete_status_codes({
        entity_type = entity_type,
        seconds = now - self.ttl_seconds,
        minutes = now - self.ttl_minutes,
      })

      if err then
        log(WARN, _log_prefix, "delete_status_codes() " .. entity_type .. " threw an error: ", err)
      end
    end

    -- release delete lock
    local query = fmt(RELEASE_LOCK_STATUS_CODES_DELETE)
    local _, err = self.connector:query(query)

    if err then
      log(WARN, _log_prefix, "err releasing delete lock ", err)
    end

    log(DEBUG, _log_prefix, "recurring postgres delete has completed")
  end

  -- start the next delete timer
  log(DEBUG, _log_prefix, "starting recurring postgres delete timer in " .. when .. " seconds")
  local ok, err = timer_at(when, delete_handler, self)
  if not ok then
    return nil, "failed to start recurring postgres delete timer: " .. err
  end
end


function _M:acquire_lock_status_codes_delete(now, when)
  local res, err

  -- If we can acquire a worker-level shm lock...
  if self:delete_lock(when) then
    -- Attempt to acquire cluster-wide delete lock
    local expiry = (when * 10) + now
    local query = fmt(ACQUIRE_LOCK_STATUS_CODES_DELETE, expiry, now)

    res, err = self.connector:query(query)

    if err then
      log(WARN, _log_prefix, "error acquiring status code lock: ", err)
    end
  end
  return res ~= nil and res.affected_rows == 1
end

-- acquire a lock for flushing counters to the database
function _M:delete_lock(when)
  local ok, err = self.list_cache:safe_add(DELETE_LOCK_KEY, true,
    when - 0.01)
  if not ok then
    if err ~= "exists" then
      log(DEBUG, _log_prefix, "failed to acquire delete lock: ", err)
    end

    return false
  end

  return true
end


--[[
  Note: all parameters are validated in vitals:get_stats()

  query_type: "seconds" or "minutes"
  level: "node" to get stats for all nodes or "cluster"
  node_id: if given, selects stats just for that node
  start_at: first timestamp, inclusive
 ]]
function _M:select_stats(query_type, level, node_id, start_ts)
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

    -- edge case, should only happen when computer has been sleeping
    if not table_names[1] then
      return {}
    end

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

  if start_ts then
    where = where .. " AND at >= " .. start_ts
  end

  -- put it all together
  query = select .. from_t1 .. where .. group

  if from_t2 then
    query = query .. " UNION " .. select .. from_t2 .. where .. group
  end

  query = query .. " ORDER BY at"

  -- BOOM
  res, err = self.connector:query(query)
  if not res then
    return nil, "could not select stats. query: " .. query .. " error: " .. err
  end

  return res
end


function _M:select_phone_home()
  local res, err = self.connector:query(fmt(SELECT_STATS_FOR_PHONE_HOME, time() - 3600, self.node_id))

  if not res then
    return nil, "could not select stats: " .. err
  end

  for k, v in pairs(res[1]) do
    if v == ngx.null then
      res[1][k] = nil
    end
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

  local nodes, err = self.connector:query(fmt(SELECT_NODES_FOR_PHONE_HOME, time() - 3600))
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

    res, err = self.connector:query(query)

    if not res then
      -- attempt to create missing table
      if match(tostring(err), "does not exist") then
        log(DEBUG, _log_prefix, "attempting to create missing table: ", tname)
        res, err = self:create_missing_seconds_table(tname)

        if not res then
          log(WARN, _log_prefix, "could not create missing table: ", err)
        else
          res, err = self.connector:query(query)
        end
      end

      -- still having issues... log it
      if not res then
        log(WARN, _log_prefix, "failed to insert seconds: ", err)
        log(DEBUG, _log_prefix, "failed query: ", query)
      end
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

    res, err = self.connector:query(query)

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

  local res, err = self.connector:query(q)

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

  local ok, err = self.connector:query(query)
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

  local res, err = self.connector:query(query)

  if err then
    return nil, "could not select nodes. query: " .. query .. " error " .. err
  end

  return res
end


function _M:update_node_meta(node_id)
  node_id = node_id or self.node_id
  local query = fmt(UPDATE_NODE_META, node_id)

  local ok, err = self.connector:query(query)
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
  local cons_id  = opts.consumer_id
  local duration = opts.duration

  if duration ~= 1 and duration ~= 60 then
    return nil, "duration must be 1 or 60"
  end

  local query = SELECT_REQUESTS_CONSUMER

  local cutoff_time

  if duration == 1 then
    cutoff_time = tonumber(opts.start_ts) or (time() - self.ttl_seconds)
  else
    cutoff_time = tonumber(opts.start_ts) or (time() - self.ttl_minutes)
  end

  query = fmt(query, cons_id, duration, cutoff_time)

  local res, err = self.connector:query(query)

  if err then
    return nil, "failed to select consumer requests. err: " .. err
  end

  return res
end


function _M:insert_consumer_stats(data, node_id)
  -- we'll query vitals_codes_per_consumer_route for this
  return true
end


function _M:insert_status_code_classes(data)
  return self:insert_status_codes(data, {
    entity_type = "cluster",
  })
end

function _M:insert_status_code_classes_by_workspace(data)
  return self:insert_status_codes(data, {
    entity_type = "workspace",
  })
end


function _M:select_status_codes(opts)
  local duration = opts.duration
  local entity_type = opts.entity_type

  if duration ~= 1 and duration ~= 60 then
    return nil, "duration must be 1 or 60"
  end

  local query = STATUS_CODE_QUERIES.SELECT[entity_type]

  if not query then
    return nil, "unknown entity_type: " .. tostring(entity_type)
  end

  local cutoff_time

  if duration == 1 then
    cutoff_time = tonumber(opts.start_ts) or (time() - self.ttl_seconds)
  else
    cutoff_time = tonumber(opts.start_ts) or (time() - self.ttl_minutes)
  end

  if entity_type == "cluster" then
    query = fmt(query, opts.duration, cutoff_time)
  else
    query = fmt(query, opts.entity_id, opts.duration, cutoff_time)
  end

  local res, err = self.connector:query(query)

  if err then
    return nil, "failed to select codes. err: " .. err
  end

  return res
end


function _M:insert_status_codes(data, opts)
  if type(opts) ~= "table" then
    return nil, "opts must be a table"
  end

  local entity_type = opts.entity_type

  if data[1] then
    local query = STATUS_CODE_QUERIES.INSERT[entity_type]

    if not query then
      return nil, "unknown entity_type: " .. tostring(entity_type)
    end

    local res, err

    -- TODO this is a hack around non-specific datatypes in our data array
    local values_fmt
    if entity_type == "service" then
      values_fmt = "%s('%s','%s',to_timestamp(%d) at time zone 'UTC',%d,%d), "
    elseif entity_type == "route" then
      values_fmt = "%s('%s','%s','%s',to_timestamp(%d) at time zone 'UTC',%d,%d), "
    elseif entity_type == "consumer_route" then
      values_fmt = "%s('%s','%s','%s','%s',to_timestamp(%d) at time zone 'UTC',%d,%d), "
    elseif entity_type == "cluster" then
      values_fmt = "%s('%s',to_timestamp(%d) at time zone 'UTC',%d,%d), "
    elseif entity_type == "workspace" then
      values_fmt = "%s('%s','%s',to_timestamp(%d) at time zone 'UTC',%d,%d), "
    end


    local values = ""
    for _, v in ipairs(data) do
      values = fmt(values_fmt, values, unpack(v))
    end

    -- strip last comma
    values = values:sub(1, -3)

    res, err = self.connector:query(fmt(query, values))

    if not res then
      return nil, "could not insert status code counters. entity_type: " ..
        entity_type .. ". error: " .. err
    end
  end

  return true
end


function _M:insert_status_codes_by_service(data)
  -- no-op for Postgres -- we'll query from vitals_status_codes_by_route
  return true
end


function _M:insert_status_codes_by_route(data)
  return self:insert_status_codes(data, {
    entity_type = "route",
  })
end


function _M:select_status_codes_by_service(opts)
  opts.entity_type = "service"
  opts.entity_id = opts.service_id

  return self:select_status_codes(opts)
end


function _M:select_status_codes_by_route(opts)
  opts.entity_type = "route"
  opts.entity_id = opts.route_id

  return self:select_status_codes(opts)
end


function _M:select_status_codes_by_consumer(opts)
  opts.entity_type = "consumer"
  opts.entity_id = opts.consumer_id

  return self:select_status_codes(opts)
end


function _M:select_status_codes_by_consumer_and_route(opts)
  opts.entity_type = "consumer_route"
  opts.entity_id = opts.consumer_id

  return self:select_status_codes(opts)
end


function _M:delete_status_codes(opts)
  if type(opts) ~= "table" then
    return nil, "opts must be a table"
  end

  -- if no cutoffs passed in, assume default
  if not opts.seconds then
    opts.seconds = time() - self.ttl_seconds
  end

  if not opts.minutes then
    opts.minutes = time() - self.ttl_minutes
  end

  if type(opts.seconds) ~= "number" then
    return nil, "opts.seconds must be a number"
  end

  if type(opts.minutes) ~= "number" then
    return nil, "opts.minutes must be a number"
  end

  local table_name = STATUS_CODE_QUERIES.DELETE[opts.entity_type]
  if not table_name then
    return nil, "unknown entity_type: " .. tostring(opts.entity_type)
  end

  local query = fmt(DELETE_CODES, table_name, 1, opts.seconds, 60, opts.minutes)

  local res, err = self.connector:query(query)

  if err then
    return nil, "failed to delete codes. err: " .. err
  end

  return res.affected_rows
end


function _M:insert_status_codes_by_consumer_and_route(data)
  return self:insert_status_codes(data, {
    entity_type = "consumer_route",
  })
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


function _M:create_missing_seconds_table(tname)
  return self.table_rotater:create_missing_seconds_table(tname)
end


function _M:node_exists(node_id)
  local query = fmt(SELECT_NODE, node_id)

  local res, err = self.connector:query(query)

  if err then
    return nil, err
  end

  return res[1] ~= nil
end


function _M:interval_width(interval)
  if interval == "seconds" then
    return 1
  end

  if interval == "minutes" then
    return 60
  end

  -- yes, doing validation at the end rather than checking 'interval' twice
  return nil, "interval must be 'seconds' or 'minutes'"
end


return _M
