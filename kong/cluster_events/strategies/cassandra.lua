local cassandra = require "cassandra"


local fmt          = string.format
local setmetatable = setmetatable


local INSERT_QUERY = [[
INSERT INTO cluster_events(channel, node_id, at, data, id, nbf)
     VALUES (?, ?, %s, ?, uuid(), ?)
      USING TTL %d
]]


local SELECT_INTERVAL_QUERY = [[
SELECT id,
       node_id,
       at,
       nbf,
       channel,
       data,
       toTimestamp(now()) as now
  FROM cluster_events
 WHERE channel IN ?
   AND at >  ?
   AND at <= %s
]]


local SERVER_TIME_QUERY = [[
SELECT toTimestamp(now()) as now
  FROM system.local
 LIMIT 1
]]


local _M = {}
local mt = { __index = _M }


function _M.new(db, page_size, event_ttl)
  if type(page_size) ~= "number" then
    error("page_size must be a number", 2)
  end

  local self  = {
    cluster   = db.connector.cluster,
    page_size = page_size,
    event_ttl = event_ttl,
  }

  return setmetatable(self, mt)
end


function _M.should_use_polling()
  return true
end

function _M:insert(node_id, channel, at, data, delay)
  local c_nbf
  if delay then
    local nbf = self:server_time() + delay
    c_nbf = cassandra.timestamp(nbf * 1000)

  else
    c_nbf = cassandra.unset
  end

  local q, args
  if at then
    q = fmt(INSERT_QUERY, "?", self.event_ttl)
    args = {
      channel,
      cassandra.uuid(node_id),
      cassandra.timestamp(at * 1000),
      data,
      c_nbf,
    }
  else

    q = fmt(INSERT_QUERY, "toTimestamp(now())", self.event_ttl)
    args = {
      channel,
      cassandra.uuid(node_id),
      data,
      c_nbf,
    }
  end

  local res, err = self.cluster:execute(q, args, {
    prepared    = true,
    consistency = cassandra.consistencies.local_one,
  })
  if not res then
    return nil, "could not insert invalidation row: " .. err
  end

  return true
end


function _M:select_interval(channels, min_at, max_at)
  local opts = {
    prepared    = true,
    page_size   = self.page_size,
    consistency = cassandra.consistencies.local_one,
  }

  local c_min_at = cassandra.timestamp((min_at or 0) * 1000)

  local query, args
  if max_at then
    local c_max_at = cassandra.timestamp(max_at * 1000)
    args  = { cassandra.set(channels), c_min_at, c_max_at }
    query = fmt(SELECT_INTERVAL_QUERY, "?")
  else
    args  = { cassandra.set(channels), c_min_at }
    query = fmt(SELECT_INTERVAL_QUERY, "toTimestamp(now())")
  end

  local iter, b, c  = self.cluster:iterate(query, args, opts)

  return function (_, p_rows)
    local rows, err, page = iter(_, p_rows)

    if rows then
      for i = 1, #rows do
        rows[i].at = rows[i].at / 1000

        if rows[i].nbf then
          rows[i].nbf = rows[i].nbf / 1000
        end

        rows[i].now = rows[i].now / 1000
      end
    end

    return rows, err, page
  end, b, c
end


function _M:truncate_events()
  return self.cluster:execute("TRUNCATE cluster_events")
end


function _M:server_time()
  local res, err = self.cluster:execute(SERVER_TIME_QUERY)
  if res then
    return res[1].now / 1000
  end

  return nil, err
end


return _M
