local cassandra = require "cassandra"


local fmt      = string.format
local match    = string.match
local math_min = math.min
local math_max = math.max
local time     = ngx.time
local log      = ngx.log
local WARN     = ngx.WARN
local INFO     = ngx.INFO
local DEBUG    = ngx.DEBUG
local unpack   = unpack

local MINUTE = 60

local _log_prefix = "[vitals-strategy] "

local _M = {}
local mt = { __index = _M }

local INSERT_SECONDS_STATS = [[
  INSERT INTO vitals_stats_seconds (node_id, at, l2_hit, l2_miss, plat_min,
      plat_max, ulat_min, ulat_max, requests, plat_count, plat_total, ulat_count,
      ulat_total)
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) IF NOT EXISTS
    USING TTL %d
]]

local INSERT_SECONDS_STATS_PARTIAL = [[
  INSERT INTO vitals_stats_seconds (node_id, at, l2_hit, l2_miss, %s, %s,
      requests, plat_count, plat_total, ulat_count, ulat_total)
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) IF NOT EXISTS
    USING TTL %d
]]

local INSERT_SECONDS_STATS_COUNTS = [[
  INSERT INTO vitals_stats_seconds (node_id, at, l2_hit, l2_miss, requests,
      plat_count, plat_total, ulat_count, ulat_total)
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?) IF NOT EXISTS
    USING TTL %d
]]

local INSERT_MINUTES_STATS = [[
  INSERT INTO vitals_stats_minutes(node_id, at, l2_hit, l2_miss, plat_min,
      plat_max, ulat_min, ulat_max, requests, plat_count, plat_total, ulat_count,
      ulat_total)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    USING TTL %d
]]

local INSERT_MINUTES_STATS_PARTIAL = [[
  INSERT INTO vitals_stats_minutes (node_id, at, l2_hit, l2_miss, %s, %s,
      requests, plat_count, plat_total, ulat_count, ulat_total)
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    USING TTL %d
]]

local INSERT_MINUTES_STATS_COUNTS = [[
  INSERT INTO vitals_stats_minutes(node_id, at, l2_hit, l2_miss, requests,
      plat_count, plat_total, ulat_count, ulat_total)
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
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

local SELECT_NODE_META = [[
  SELECT node_id, hostname FROM vitals_node_meta
  WHERE node_id IN ?
]]

local SELECT_STATS = [[
  SELECT node_id, at, l2_hit, l2_miss, plat_min, plat_max, ulat_min, ulat_max,
    requests, plat_count, plat_total, ulat_count, ulat_total
  FROM %s
  WHERE node_id IN ?
    AND at >= ?
]]

local SELECT_STATS_FOR_PHONE_HOME = [[
  SELECT l2_hit, l2_miss, plat_min, plat_max, ulat_min, ulat_max, plat_count,
      plat_total, ulat_count, ulat_total
  FROM vitals_stats_minutes
  WHERE node_id = ?
  LIMIT 60
]]

local SELECT_NODES_FOR_PHONE_HOME = [[
  SELECT node_id
  FROM vitals_node_meta
  WHERE last_report >= ?
  ALLOW FILTERING
]]

local INSERT_CONSUMER_STATS = [[
  UPDATE vitals_consumers
     SET count       = count + ?
   WHERE at          = ?
     AND duration    = ?
     AND consumer_id = ?
     AND node_id     = ?
]]

local SELECT_CONSUMER_STATS = [[
  SELECT node_id, at, count
  FROM vitals_consumers
  WHERE consumer_id = ? AND duration = ? AND at >= ?
]]

local DELETE_CONSUMER_STATS = [[
  DELETE FROM vitals_consumers
  WHERE consumer_id = ? AND duration = ? AND at < ?
]]

local INSERT_CODE_CLASSES_CLUSTER = [[
  UPDATE vitals_code_classes_by_cluster
     SET count = count + ?
   WHERE at = ?
     AND duration = ?
     AND code_class = ?
]]

local SELECT_CODE_CLASSES_CLUSTER = [[
  SELECT code_class, at, count
    FROM vitals_code_classes_by_cluster
   WHERE code_class in (1, 2, 3, 4, 5)
     AND duration = ? AND at >= ?
]]

local DELETE_CODE_CLASSES_CLUSTER = [[
  DELETE FROM vitals_code_classes_by_cluster
  WHERE code_class in (1, 2, 3, 4, 5)
  AND duration = ? AND at < ?
]]

local INSERT_CODE_CLASSES_WORKSPACE = [[
  UPDATE vitals_code_classes_by_workspace
     SET count = count + ?
   WHERE at = ?
     AND duration = ?
     AND code_class = ?
     AND workspace_id = ?
]]

local SELECT_CODE_CLASSES_WORKSPACE = [[
  SELECT code_class, at, count
    FROM vitals_code_classes_by_workspace
   WHERE workspace_id = ?
     AND duration = ? AND at >= ?
]]

local INSERT_CODES_BY_SERVICE = [[
  UPDATE vitals_codes_by_service
     SET count = count + ?
   WHERE at = ?
     AND duration = ?
     AND code = ?
     AND service_id = ?
]]

local INSERT_CODES_BY_ROUTE = [[
  UPDATE vitals_codes_by_route
     SET count = count + ?
   WHERE at = ?
     AND duration = ?
     AND code = ?
     AND route_id = ?
]]

local INSERT_CODES_BY_CONSUMER_AND_ROUTE = [[
  UPDATE vitals_codes_by_consumer_route
     SET count = count + ?
   WHERE at = ?
     AND duration = ?
     AND code = ?
     AND consumer_id = ?
     AND route_id = ?
     AND service_id = ?
]]

local SELECT_CODES_SERVICE = [[
  SELECT service_id, code, at, count
    FROM vitals_codes_by_service
   WHERE service_id = ? AND duration = ? AND at >= ?
]]

local SELECT_CODES_ROUTE = [[
  SELECT route_id, code, at, count
    FROM vitals_codes_by_route
   WHERE route_id = ? AND duration = ? AND at >= ?
]]

local SELECT_CODES_CONSUMER = [[
  SELECT consumer_id, code, at, count
    FROM vitals_codes_by_consumer_route
   WHERE consumer_id = ? AND duration = ? AND at >= ?
]]

local SELECT_CODES_CONSUMER_ROUTE = [[
  SELECT consumer_id, route_id, code, at, count
    FROM vitals_codes_by_consumer_route
   WHERE consumer_id = ? AND duration = ? AND at >= ?
]]

local DELETE_CODES_SERVICE = [[
  DELETE FROM vitals_codes_by_service
   WHERE service_id = ? AND duration = ? AND at < ?
]]

local DELETE_CODES_ROUTE = [[
  DELETE FROM vitals_codes_by_route
   WHERE route_id = ? AND duration = ? AND at < ?
]]

local DELETE_CODE_CLASSES_WORKSPACE = [[
  DELETE FROM vitals_code_classes_by_workspace
   WHERE workspace_id = ? AND duration = ? AND at < ?
]]

local STATUS_CODE_QUERIES = {
  SELECT = {
    cluster        = SELECT_CODE_CLASSES_CLUSTER,
    workspace      = SELECT_CODE_CLASSES_WORKSPACE,
    consumer_route = SELECT_CODES_CONSUMER_ROUTE,
    consumer       = SELECT_CODES_CONSUMER,
    service        = SELECT_CODES_SERVICE,
    route          = SELECT_CODES_ROUTE,
  },
  INSERT = {
    workspace      = INSERT_CODE_CLASSES_WORKSPACE,
    consumer_route = INSERT_CODES_BY_CONSUMER_AND_ROUTE,
    service        = INSERT_CODES_BY_SERVICE,
    route          = INSERT_CODES_BY_ROUTE,
  },
  DELETE = {
    service        = DELETE_CODES_SERVICE,
    route          = DELETE_CODES_ROUTE,
    workspace      = DELETE_CODE_CLASSES_WORKSPACE,
  }
}

local QUERY_OPTIONS = {
  prepared = true,
}

local COUNTER_QUERY_OPTIONS = {
  prepared = true,
  counter  = true,
}

-- performs the requested fn on v1 and v2 as long as they're both numeric
-- otherwise, this will return... something
local function aggregate_values(v1, v2, fn)
  if type(v2) ~= "number" then
    return v1
  end

  if type(v1) ~= "number" then
    return v2
  end

  return fn(v1, v2)
end


-- merge t2 into t1. both are hashes (not arrays) of stat_name:stat_value
-- if either contains a timestamp ("at"), that key is ignored -- it is up
-- to the caller to manage timestamps, as those are not aggregatable.
local function aggregate_stats(t1, t2)
  t1.l2_hit  = t1.l2_hit + t2.l2_hit
  t1.l2_miss = t1.l2_miss + t2.l2_miss

  t1.plat_min = aggregate_values(t1.plat_min, t2.plat_min, math_min)
  t1.plat_max = aggregate_values(t1.plat_max, t2.plat_max, math_max)

  t1.ulat_min = aggregate_values(t1.ulat_min, t2.ulat_min, math_min)
  t1.ulat_max = aggregate_values(t1.ulat_max, t2.ulat_max, math_max)

  t1.requests = t1.requests + (t2.requests)

  t1.plat_count = t1.plat_count + (t2.plat_count)
  t1.plat_total = t1.plat_total + (t2.plat_total)

  t1.ulat_count = t1.ulat_count + (t2.ulat_count)
  t1.ulat_total = t1.ulat_total + (t2.ulat_total)
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
        ulat_min = nil,
        ulat_max = nil,
        requests = 0,
        plat_count = 0,
        plat_total = 0,
        ulat_count = 0,
        ulat_total = 0,
        node_id = "cluster"
      })

      -- save its index in the timestamp_to_index hash
      timestamp_to_index[row.at] = #cluster_stats
    end

    -- add the current row to the accumulator
    aggregate_stats(cluster_stats[timestamp_to_index[row.at]], row)
  end

  return cluster_stats
end


function _M.new(dao_factory, opts)
  if not opts then
    opts = {}
  end

  local self = {
    db          = dao_factory.db,
    cluster     = dao_factory.db.cluster,
    ttl_seconds = opts.ttl_seconds or 3600,
    ttl_minutes = opts.ttl_minutes or 90000,
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
    return nil, "could not record node meta data. query: " .. RECORD_NODE ..
        " error: " .. err
  end

  return true
end


function _M:select_stats(query_type, level, node_id, start_ts)
  local tname, not_before_ts
  local now = time()
  local node_ids = {}
  local res = {}

  -- If node_id is nil (cluster level or node level with nil node_id passed)
  -- Query db for list of nodes
  if node_id == nil then
    for rows, err, page in self.cluster:iterate(SELECT_NODES) do
      if err then
        return nil, "failed to select nodes. page: " .. page .. " error: " .. err
      end

       -- map the node ids to array, cast to cassandra uuid
      for i = 1, #rows do
        table.insert(node_ids, cassandra.uuid(rows[i].node_id))
      end
    end

  else
    -- otherwise, we have a single requested node_id
    node_ids[1] = cassandra.uuid(node_id)
  end

  -- construct query
  if query_type == "seconds" then
    not_before_ts = tonumber(start_ts) or (now - self.ttl_seconds)
    tname = "vitals_stats_seconds"

  elseif query_type == "minutes" then
    not_before_ts = tonumber(start_ts) or (now - self.ttl_minutes)
    tname = "vitals_stats_minutes"

  end

  local args = {
    node_ids,
    cassandra.timestamp(not_before_ts * 1000)
  }

  for rows, err, page in self.cluster:iterate(fmt(SELECT_STATS, tname), args, QUERY_OPTIONS) do
    if err then
      return nil, "could not select stats. error: " .. err
    end

    for i = 1, #rows do
      -- someday we'll be able to do this math in the db!
      rows[i].at = rows[i].at / 1000
      table.insert(res, rows[i])
    end
  end

  -- if cluster level, aggregate stats into a single node_id key "cluster"
  if level == "cluster" then
    return aggregate_cluster(res)
  end

  return res
end

function _M:select_phone_home()
  local err, res
  local acc = {}
  local plat_count = 0
  local plat_total = 0
  local ulat_count = 0
  local ulat_total = 0

  local at = cassandra.timestamp((time() - 3600) * 1000)

  res, err = self.cluster:execute(SELECT_STATS_FOR_PHONE_HOME, { self.node_id }, QUERY_OPTIONS)

  if err then
    return nil, "could not select stats: " .. err
  end

  for i = 1, #res do
    acc["v.cdht"] = (acc["v.cdht"] or 0) + res[i].l2_hit
    acc["v.cdmt"] = (acc["v.cdmt"] or 0) + res[i].l2_miss
    acc["v.lprn"] = aggregate_values(acc["v.lprn"], res[i].plat_min, math_min)
    acc["v.lprx"] = aggregate_values(acc["v.lprx"], res[i].plat_max, math_max)
    acc["v.lun"]  = aggregate_values(acc["v.lun"], res[i].ulat_min, math_min)
    acc["v.lux"]  = aggregate_values(acc["v.lux"], res[i].ulat_max, math_max)
    plat_count = plat_count + res[i].plat_count
    plat_total = plat_total + res[i].plat_total
    ulat_count = ulat_count + res[i].ulat_count
    ulat_total = ulat_total + res[i].ulat_total
  end

  if plat_count > 0 then
    acc["v.lpra"] = math.floor(plat_total / plat_count + 0.5)
  end

  if ulat_count > 0 then
    acc["v.lua"] = math.floor(ulat_total / ulat_count + 0.5)
  end

  res, err = self.cluster:execute(SELECT_NODES_FOR_PHONE_HOME, { at }, QUERY_OPTIONS)

  if err then
    -- v2.x doesn't support range queries on last_report. Ignore that,
    -- but log any others
    if not match(tostring(err), "Predicates on non[-]primary[-]key") then
      log(WARN, _log_prefix, "could not count nodes: ", err)
    end
  end

  -- if we couldn't get a count, just don't include it in the results
  acc["v.nt"] = res and #res or nil

  return { acc }
end


-- the logic to avoid inserting nulls is tedious and will become moreso
-- as we add non-counter stats over time. Consolidate that mess into
-- one function to be used by insert_stats(), insert_minutes(), perhaps
-- eventually even insert_hours()
local function prepare_insert_stats_statement(row, node, at, interval, ttl)
  if interval ~= "minutes" and interval ~= "seconds" then
    return nil, "interval must be 'minutes' or 'seconds'"
  end

  local query, format_params

  local args = {
    node,
    at,
    row.l2_hit,
    row.l2_miss,
  }

  local i = 4

  -- which query to use?
  -- happy path: we have both proxy and upstream latencies
  if row.plat_min and row.ulat_min then
    log(DEBUG, _log_prefix, "inserting full row")

    format_params = { ttl }

    if interval == "seconds" then
      query = INSERT_SECONDS_STATS
    else
      query = INSERT_MINUTES_STATS
    end

    args[5] = row.plat_min
    args[6] = row.plat_max
    args[7] = row.ulat_min
    args[8] = row.ulat_max
    i = 8

  else
    -- we don't have both. which if any do we have?
    if row.plat_min then
      log(DEBUG, _log_prefix, "inserting partial row (plat)")

      format_params = { "plat_min", "plat_max", ttl }

      if interval == "seconds" then
        query = INSERT_SECONDS_STATS_PARTIAL
      else
        query = INSERT_MINUTES_STATS_PARTIAL
      end

      args[5] = row.plat_min
      args[6] = row.plat_max
      i = 6

    elseif row.ulat_min then
      log(DEBUG, _log_prefix, "inserting partial row (ulat)")

      format_params = { "ulat_min", "ulat_max", ttl }

      if interval == "seconds" then
        query = INSERT_SECONDS_STATS_PARTIAL
      else
        query = INSERT_MINUTES_STATS_PARTIAL
      end

      args[5] = row.ulat_min
      args[6] = row.ulat_max
      i = 6

    else
      -- don't have either
      log(DEBUG, _log_prefix, "inserting partial row (counts only)")

      format_params = { ttl }

      if interval == "seconds" then
        query = INSERT_SECONDS_STATS_COUNTS
      else
        query = INSERT_MINUTES_STATS_COUNTS
      end

    end
  end

  query = fmt(query, unpack(format_params))

  -- append the rest of the arguments in the right place
  args[i + 1] = row.requests
  args[i + 2] = row.plat_count
  args[i + 3] = row.plat_total
  args[i + 4] = row.ulat_count
  args[i + 5] = row.ulat_total

  return query, args
end


function _M:insert_stats(data, node_id)
  local at, hit, miss, plat_min, plat_max, ulat_min, ulat_max, requests,
    plat_count, plat_total, ulat_count, ulat_total, query, args, res, err
  local now = time()
  local node

  -- passing node_id is for ease of testing
  if node_id then
    node = cassandra.uuid(node_id)
  else
    node = self.node_id
  end

  -- as we loop over our seconds, we'll calculate the minutes data to insert
  local mdata = {} -- array of data to insert
  local midx  = {} -- table of timestamp to array index
  local mnext = 1  -- next index in mdata

  for _, row in ipairs(data) do
    at, hit, miss, plat_min, plat_max, ulat_min, ulat_max, requests, plat_count,
      plat_total, ulat_count, ulat_total = unpack(row)

    local mat = self:get_bucket(at, MINUTE)
    local i   = midx[mat]
    if i then
      mdata[i]["l2_hit"] = mdata[i]["l2_hit"] + hit
      mdata[i]["l2_miss"] = mdata[i]["l2_miss"] + miss
      mdata[i]["plat_min"] = aggregate_values(mdata[i]["plat_min"], plat_min, math_min)
      mdata[i]["plat_max"] = aggregate_values(mdata[i]["plat_max"], plat_max, math_max)
      mdata[i]["ulat_min"] = aggregate_values(mdata[i]["ulat_min"], ulat_min, math_min)
      mdata[i]["ulat_max"] = aggregate_values(mdata[i]["ulat_max"], ulat_max, math_max)
      mdata[i]["requests"] = mdata[i]["requests"] + requests
      mdata[i]["plat_count"] = mdata[i]["plat_count"] + plat_count
      mdata[i]["plat_total"] = mdata[i]["plat_total"] + plat_total
      mdata[i]["ulat_count"] = mdata[i]["ulat_count"] + ulat_count
      mdata[i]["ulat_total"] = mdata[i]["ulat_total"] + ulat_total
    else
      mdata[mnext] = {
        at = mat,
        l2_hit = hit,
        l2_miss = miss,
        plat_min = plat_min,
        plat_max = plat_max,
        ulat_min = ulat_min,
        ulat_max = ulat_max,
        requests = requests,
        plat_count = plat_count,
        plat_total = plat_total,
        ulat_count = ulat_count,
        ulat_total = ulat_total,
      }
      midx[mat] = mnext
      mnext  = mnext + 1
    end

    local stat_table = {
      l2_hit = hit,
      l2_miss = miss,
      plat_min = plat_min,
      plat_max = plat_max,
      ulat_min = ulat_min,
      ulat_max = ulat_max,
      requests = requests,
      plat_count = plat_count,
      plat_total = plat_total,
      ulat_count = ulat_count,
      ulat_total = ulat_total,
    }

    query, args = prepare_insert_stats_statement(
        stat_table,
        node,
        cassandra.timestamp(at * 1000),
        "seconds",
        self.ttl_seconds
    )

    -- insert seconds rows
    res, err = self.cluster:execute(query, args, QUERY_OPTIONS)

    if err then
      log(WARN, _log_prefix, "could not insert stats: " .. err)
    elseif res and res[1] and not res[1]["[applied]"] then
      log(INFO, _log_prefix, "insert failed, row exists")
    end
  end

  -- insert minutes
  local _, err = self:insert_minutes(mdata, node_id)
  if err then
    log(WARN, _log_prefix, "failed to aggregate minutes: " .. err)
  end

  -- finally, update last_reported in vitals_node_meta
  res, err = self.cluster:execute(UPDATE_NODE, {
    cassandra.timestamp(now * 1000),
    node,
  }, QUERY_OPTIONS)

  if not res then
    log(WARN, _log_prefix, "failed to update node: " .. err)
  end

  return true
end


local function new_row()
  return {
    l2_hit = 0,
    l2_miss = 0,
    plat_min = nil,
    plat_max = nil,
    ulat_min = nil,
    ulat_max = nil,
    requests = 0,
    plat_count = 0,
    plat_total = 0,
    ulat_count = 0,
    ulat_total = 0,
  }
end


function _M:insert_minutes(minutes, node_id)
  if not minutes[1] then
    -- nothing to do
    return 0
  end

  -- passing node_id is for ease of testing
  local node
  if node_id then
    node = cassandra.uuid(node_id)
  else
    node = self.node_id
  end

  local query, args, at, res, err
  local inserted = 0

  local select_q = "select * from vitals_stats_minutes where node_id = ? and at = ?"

  for _, m in ipairs(minutes) do
    at = cassandra.timestamp(m.at * 1000)

    -- select the existing data
    res, err = self.cluster:execute(select_q, {
        node,
        at,
      },
      QUERY_OPTIONS
    )

    local row
    if err then
      log(WARN, _log_prefix, "failed to select minute: " .. err)
      row = new_row()
    else
      row = res[1] or new_row()
    end

    -- aggregate it
    aggregate_stats(row, m)

    -- save it. avoid inserting nulls
    query, args = prepare_insert_stats_statement(
      row,
      node,
      at,
      "minutes",
      self.ttl_minutes
    )

    local _, err = self.cluster:execute(query, args, QUERY_OPTIONS)

    if err then
      log(WARN, _log_prefix, "failed to insert minute: " .. err)
    else
      inserted = inserted + 1
    end
  end

  return inserted
end


function _M:delete_stats(cutoff_times)
  -- this is a no-op for Cassandra
  return 0
end


function _M:current_table_name()
  return nil
end


-- returns the bucket for a given epoch timestamp
-- bucket size is one of MINUTE, HOUR, DAY
function _M:get_bucket(at, size)
  return at - (at % size)
end


function _M:insert_status_code_classes(data)
  local res, err, count, at, duration, code_class

  for _, row in ipairs(data) do
    code_class, at, duration, count = unpack(row)

    local count_converted = cassandra.counter(count)
    local at_converted = cassandra.timestamp(at * 1000)

    res, err = self.cluster:execute(INSERT_CODE_CLASSES_CLUSTER, {
      count_converted,
      at_converted,
      tonumber(duration),
      tonumber(code_class),
    }, COUNTER_QUERY_OPTIONS)


    if not res then
      return nil, "could not insert status code counters. error: " .. err
    end
  end

  -- non-optional cleanup.
  local _, err = self:delete_status_code_classes()
  if err then
    log(WARN, _log_prefix, "failed to delete status code classes: ", err)
  end

  return true
end

function _M:delete_status_code_classes(cutoff_times)
  if self.db.major_version_n < 3 then
    -- the delete algorithm implemented below doesn't work on 2.x
    -- this is documented as a known issue, so we aren't going to log it
    -- or fail here.
    return 1
  end

  -- if nothing passed in, use defaults
  if not cutoff_times then
    local now = time()
    cutoff_times = {
      seconds = now - self.ttl_seconds,
      minutes = now - self.ttl_minutes,
    }
  end

  local _, err = self.cluster:execute(DELETE_CODE_CLASSES_CLUSTER, {
    1,
    cassandra.timestamp(cutoff_times.seconds * 1000),
  })

  if err then
    return nil, err
  end

  _, err = self.cluster:execute(DELETE_CODE_CLASSES_CLUSTER, {
    60,
    cassandra.timestamp(cutoff_times.minutes * 1000),
  })

  if err then
    return nil, err
  end

  -- note this isn't a true count since c* won't tell us how many rows she
  -- deleted. Basically, anything non-zero means _something_ happened. <sigh/>
  return 1
end


function _M:insert_status_code_classes_by_workspace(data)
  return self:insert_status_codes(data, {
    entity_type = "workspace",
    prune = true,
  })
end


function _M:insert_status_codes_by_service(data)
  return self:insert_status_codes(data, {
    entity_type = "service",
    prune = true,
  })
end


function _M:delete_status_codes_by_service(services, cutoff_times)
  local opts = {
    entity_type = "service",
    entities = services,
    seconds_before = cutoff_times.seconds,
    minutes_before = cutoff_times.minutes,
  }

  return self:delete_status_codes(opts)
end


function _M:insert_status_codes_by_route(data)
  return self:insert_status_codes(data, {
    entity_type = "route",
    prune = true,
  })
end


function _M:select_status_codes(opts)
  local entity_type = opts.entity_type
  local query       = STATUS_CODE_QUERIES.SELECT[entity_type]

  if not query then
    return nil, "unknown entity_type: " .. tostring(entity_type)
  end

  local duration = opts.duration

  if duration ~= 1 and duration ~= 60 then
    return nil, "duration must be 1 or 60"
  end

  local cutoff_time, args

  if duration == 1 then
    cutoff_time = tonumber(opts.start_ts) or (time() - self.ttl_seconds)
  else
    cutoff_time = tonumber(opts.start_ts) or (time() - self.ttl_minutes)
  end

  if entity_type == "cluster" then
    args = {
      duration,
      cassandra.timestamp(cutoff_time * 1000),
    }
  else
    args = {
      cassandra.uuid(opts.entity_id),
      duration,
      cassandra.timestamp(cutoff_time * 1000),
    }
  end

  local res = {}
  local idx = 1

  for rows, err, page in self.cluster:iterate(query, args, QUERY_OPTIONS) do
    if err then
      return nil, "could not select codes. error: " .. err
    end

    for _, row in ipairs(rows) do
      row.at = row.at / 1000
      res[idx] = row
      idx = idx + 1
    end
  end

  return res
end


function _M:delete_status_codes_by_route(routes, cutoff_times)
  local opts = {
    entity_type = "route",
    entities = routes,
    seconds_before = cutoff_times.seconds,
    minutes_before = cutoff_times.minutes,
  }

  return self:delete_status_codes(opts)
end


function _M:delete_status_codes(opts)
  local entity_type    = opts.entity_type
  local entities       = opts.entities
  local seconds_before = opts.seconds_before
  local minutes_before = opts.minutes_before

  if self.db.major_version_n < 3 then
    -- the delete algorithm implemented below doesn't work on 2.x
    -- this is documented as a known issue, so we aren't going to log it
    -- or fail here.
    return 1
  end

  local query = STATUS_CODE_QUERIES.DELETE[entity_type]

  if not query then
    return nil, "unknown entity_type: " .. tostring(entity_type)
  end

  local count = 0

  for k, _ in pairs(entities) do
    local _, err = self.cluster:execute(query, {
      cassandra.uuid(k),
      1,
      cassandra.timestamp(seconds_before * 1000),
    })

    if err then
      log(WARN, _log_prefix, "failed to delete codes by " .. entity_type .. "(secs). err: ", err)
    else
      count = count + 1
    end

    _, err = self.cluster:execute(query, {
      cassandra.uuid(k),
      60,
      cassandra.timestamp(minutes_before * 1000),
    })

    if err then
      log(WARN, _log_prefix, "failed to delete codes by " .. entity_type .. "(mins). err: ", err)
    else
      count = count + 1
    end
  end

  -- note this isn't a true count since c* won't tell us how many rows she
  -- deleted. Basically, anything non-zero means _something_ happened. <sigh/>
  return count
end


function _M:insert_status_codes(data, opts)
  if type(opts) ~= "table" then
    return nil, "opts must be a table"
  end

  local entity_type = opts.entity_type
  local prune       = opts.prune
  local query       = STATUS_CODE_QUERIES.INSERT[entity_type]

  if not query then
    return nil, "unknown entity_type: " .. tostring(entity_type)
  end

  local entities_to_delete = {}

  local res, err, entity_id, route_id, service_id, at, duration, code, count

  for _, v in ipairs(data) do
    -- TODO: obviate the need for this check
    if entity_type == "service" or entity_type == "workspace" then
      entity_id, code, at, duration, count = unpack(v)
    elseif entity_type == "consumer_route" then
      entity_id, route_id, service_id, code, at, duration, count = unpack(v)
    else
      entity_id, _, code, at, duration, count = unpack(v)
    end

    local insert_data = {
      cassandra.counter(count),
      cassandra.timestamp(at * 1000),
      tonumber(duration),
      tonumber(code),
      cassandra.uuid(entity_id),
    }

    if entity_type == "consumer_route" then
      local ids = { route_id, service_id }

      for _, id in ipairs(ids) do
        table.insert(insert_data, cassandra.uuid(id))
      end
    end

    res, err = self.cluster:execute(query, insert_data, COUNTER_QUERY_OPTIONS)

    -- TODO: if we break here, we don't do any cleanup
    if not res then
      return nil, "insert_status_codes failed: " .. err
    end

    if prune then
      entities_to_delete[entity_id] = true
    end
  end

  if prune then
    local now = time()

    self:delete_status_codes({
      entity_type    = entity_type,
      entities       = entities_to_delete,
      seconds_before = now - self.ttl_seconds,
      minutes_before = now - self.ttl_minutes,
    })
  end

  return true
end


function _M:insert_status_codes_by_consumer_and_route(data)
  return self:insert_status_codes(data, {
    entity_type = "consumer_route",
    prune = true,
  })
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

  local consumers_to_delete = {}

  for _, row in ipairs(data) do
    consumer_id, at, duration, count = unpack(row)

    local count_converted = cassandra.counter(count)
    local now_converted = cassandra.timestamp(at * 1000)
    local consumer_id_converted = cassandra.uuid(consumer_id)

    res, err = self.cluster:execute(INSERT_CONSUMER_STATS, {
      count_converted,
      now_converted,
      tonumber(duration),
      consumer_id_converted,
      node_id,
    }, COUNTER_QUERY_OPTIONS)


    if not res then
      return nil, "could not insert consumer stats. error: " .. err
    end

    consumers_to_delete[consumer_id] = true
  end

  local _, err = self:delete_consumer_stats(consumers_to_delete)
  if err then
    return nil, "failed to clean up consumer stats: " .. err
  end

  return true
end


function _M:select_consumer_stats(opts)
  local level    = opts.level
  local node_id  = opts.node_id
  local cons_id  = opts.consumer_id
  local duration = opts.duration

  if duration ~= 1 and duration ~= 60 then
    return nil, "duration must be 1 or 60"
  end

  local cutoff_time, args

  if duration == 1 then
    cutoff_time = tonumber(opts.start_ts) or (time() - self.ttl_seconds)
  else
    cutoff_time = tonumber(opts.start_ts) or (time() - self.ttl_minutes)
  end

  args = {
    cassandra.uuid(cons_id),
    duration,
    cassandra.timestamp(cutoff_time * 1000),
  }

  local res = {}
  local idx = 1
  local cidx = {}
  for rows, err, page in self.cluster:iterate(SELECT_CONSUMER_STATS, args, QUERY_OPTIONS) do
    if err then
      return nil, "could not select consumer stats. error: " .. err
    end

    for i, row in ipairs(rows) do
      row.at = row.at / 1000

      if level == "node" then
        -- all nodes, or just one?
        if node_id then
          if row.node_id == node_id then
            res[idx] = row
            idx = idx + 1
          end
        else
          res[i] = row
        end
      else
        -- must be cluster
        -- have we seen this timestamp already?
        if cidx[row.at] then
          res[cidx[row.at]].count = res[cidx[row.at]].count + row.count
        else
          cidx[row.at] = idx
          res[idx] = row
          res[idx].node_id = "cluster"
          idx = idx + 1
        end
      end
    end
  end

  return res
end


function _M:delete_consumer_stats(consumers, cutoff_times)
  if self.db.major_version_n < 3 then
    -- the delete algorithm implemented below doesn't work on 2.x
    -- this is documented as a known issue, so we aren't going to log it
    -- or fail here.
    return 1
  end

  if not cutoff_times then
    local now = time()
    cutoff_times = {
      seconds = now - self.ttl_seconds,
      minutes = now - self.ttl_minutes,
    }
  end

  for k, _ in pairs(consumers) do
    local _, err = self.cluster:execute(DELETE_CONSUMER_STATS, {
      cassandra.uuid(k),
      1,
      cassandra.timestamp(cutoff_times.seconds * 1000),
    })

    if err then
      return nil, err
    end

    _, err = self.cluster:execute(DELETE_CONSUMER_STATS, {
      cassandra.uuid(k),
      60,
      cassandra.timestamp(cutoff_times.minutes * 1000),
    })

    if err then
      return nil, err
    end
  end

  -- note this isn't a true count since c* won't tell us how many rows she
  -- deleted. Basically, anything non-zero means _something_ happened. <sigh/>
  return 1
end


function _M:node_exists(node_id)
  if node_id == nil then
    return false
  end

  local res, err = self.cluster:execute(SELECT_NODE, {
    cassandra.uuid(node_id),
  }, QUERY_OPTIONS)

  if err then
    return nil, err
  end

  return res[1] ~= nil
end


function _M:select_node_meta(node_ids)
  if not node_ids or not node_ids[1] then
    return {}
  end

  -- convert to cassandra uuid
  for i, v in ipairs(node_ids) do
    node_ids[i] = cassandra.uuid(v)
  end

  local res = {}

  for rows, err, page in self.cluster:iterate(SELECT_NODE_META, {node_ids}, QUERY_OPTIONS) do
    if err then
      return nil, "failed to select nodes. page: " .. page .. " query: " .. SELECT_NODES .. " error: " .. err
    end

    for i = 1, #rows do
      table.insert(res, rows[i])
    end
  end

  return res
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
