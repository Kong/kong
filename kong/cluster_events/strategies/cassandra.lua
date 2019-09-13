local cassandra = require "cassandra"


local fmt          = string.format
local setmetatable = setmetatable
local kong         = kong


local INSERT_QUERY = [[
INSERT INTO cluster_events(channel, node_id, at, data, id, nbf)
 VALUES(?, ?, ?, ?, uuid(), ?)
 USING TTL %d
]]

local SELECT_INTERVAL_QUERY = [[
SELECT * FROM cluster_events
 WHERE channel IN ?
   AND at  >  ?
   AND at  <= ?
]]


local _M = {}
local mt = { __index = _M }


function _M.new(db, page_size, event_ttl)
  local self  = {
    cluster   = db.connector.cluster,
    page_size = page_size or 100,
    event_ttl = event_ttl,
  }

  return setmetatable(self, mt)
end


function _M.should_use_polling()
  return true
end


function _M:insert(node_id, channel, at, data, nbf)
  local c_nbf
  if nbf then
    c_nbf = cassandra.timestamp(nbf * 1000)

  else
    c_nbf = cassandra.unset
  end

  local q = fmt(INSERT_QUERY, self.event_ttl)

  local res, err = self.cluster:execute(q, {
    channel,
    cassandra.uuid(node_id),
    cassandra.timestamp(at * 1000),
    data,
    c_nbf,
  }, {
    prepared    = true,
    consistency = cassandra.consistencies[kong.configuration.cassandra_consistency:lower()],
  })
  if not res then
    return nil, "could not insert invalidation row: " .. err
  end

  return true
end


function _M:select_interval(channels, min_at, max_at)
  local c_min_at = cassandra.timestamp(min_at * 1000)
  local c_max_at = cassandra.timestamp(max_at * 1000)

  local args = { cassandra.set(channels), c_min_at, c_max_at }
  local opts = {
    prepared      = true,
    page_size     = self.page_size,
    consistencies = cassandra.consistencies[kong.configuration.cassandra_consistency:lower()],
  }

  local iter, b, c = self.cluster:iterate(SELECT_INTERVAL_QUERY, args, opts)

  return function (_, p_rows)
    local rows, err, page = iter(_, p_rows)

    if rows then
      for i = 1, #rows do
        if rows[i].nbf then
          rows[i].nbf = rows[i].nbf / 1000
        end
      end
    end

    return rows, err, page
  end, b, c
end


function _M:truncate_events()
  return self.cluster:execute("TRUNCATE cluster_events")
end


return _M
