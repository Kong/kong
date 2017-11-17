local table_rotater_module = require "kong.vitals.postgres.table_rotater"
local fmt                  = string.format
local unpack               = unpack


local _M = {}
local mt = { __index = _M }


local INSERT_STATS = [[
  insert into %s (at, node_id, l2_hit, l2_miss, plat_min, plat_max)
  values (%d, '%s', %d, %d, %s, %s)
  on conflict (node_id, at) do update set
    l2_hit = %s.l2_hit + excluded.l2_hit,
    l2_miss = %s.l2_miss + excluded.l2_miss,
    plat_min = least(%s.plat_min, excluded.plat_min),
    plat_max = greatest(%s.plat_max, excluded.plat_max)
]]

local UPDATE_NODE_META = "update vitals_node_meta set last_report = now() where node_id = '%s'"

function _M.new(dao_factory, opts)
  local table_rotater = table_rotater_module.new(
    {
      db = dao_factory.db,
      rotation_interval = opts.postgres_rotation_interval,
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
             max(plat_max) as plat_max
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

    query = fmt(INSERT_STATS, table_name, at, self.node_id, hit, miss, plat_min,
                plat_max, table_name, table_name, table_name, table_name)

    res, err = self.db:query(query)

    if not res then
      return nil, "could not insert stats. query: " .. query .. " error: " .. err
    end
  end

  local ok, err = self:update_node_meta()
  if not ok then
    return nil, "could not update metadata. query: " .. query .. " error: " .. err
  end

  return true
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


function _M:update_node_meta()
  local query = fmt(UPDATE_NODE_META, self.node_id)

  local ok, err = self.db:query(query)
  if not ok then
    return nil, "could not update metadata. query: " .. query  .. " error " .. err
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
