local constants = require "kong.constants"
local utils  = require "kong.tools.utils"


local max          = math.max
local fmt          = string.format
local null         = ngx.null
local concat       = table.concat
local tonumber     = tonumber
local setmetatable = setmetatable


local new_tab
do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function(narr, nrec) return {} end
  end
end


local INSERT_QUERY = [[
INSERT INTO cluster_events (
  "id",
  "node_id",
  "at",
  "nbf",
  "expire_at",
  "channel",
  "data"
) VALUES (
  %s,
  %s,
  TO_TIMESTAMP(%s) AT TIME ZONE 'UTC',
  TO_TIMESTAMP(%s) AT TIME ZONE 'UTC',
  TO_TIMESTAMP(%s) AT TIME ZONE 'UTC',
  %s,
  %s
)
]]


local SELECT_INTERVAL_QUERY = [[
  SELECT "id",
         "node_id",
         "channel",
         "data",
         EXTRACT(EPOCH FROM "at"  AT TIME ZONE 'UTC') AS "at",
         EXTRACT(EPOCH FROM "nbf" AT TIME ZONE 'UTC') AS "nbf"
    FROM "cluster_events"
   WHERE "channel" IN (%s)
     AND "at" >  TO_TIMESTAMP(%s) AT TIME ZONE 'UTC'
     AND "at" <= TO_TIMESTAMP(%s) AT TIME ZONE 'UTC'
ORDER BY "at"
   LIMIT %s
  OFFSET %s
]]


local _M = {}


local mt = { __index = _M }


function _M.new(db, page_size, event_ttl)
  local self  = {
    connector = db.connector,
    page_size = page_size or constants.DEFAULT_CLUSTER_EVENTS_PAGE_SIZE,
    event_ttl = event_ttl,
  }

  return setmetatable(self, mt)
end


function _M.should_use_polling()
  return true
end


function _M:insert(node_id, channel, at, data, nbf)
  local expire_at = max(at + self.event_ttl, at)
  expire_at = self.connector:escape_literal(tonumber(fmt("%.3f", expire_at)))

  if not nbf then
    nbf = "NULL"
  else
    nbf = self.connector:escape_literal(tonumber(fmt("%.3f", nbf)))
  end

  local pg_id      = self.connector:escape_literal(utils.uuid())
  local pg_node_id = self.connector:escape_literal(node_id)
  local pg_channel = self.connector:escape_literal(channel)
  local pg_data    = self.connector:escape_literal(data)

  local q = fmt(INSERT_QUERY, pg_id, pg_node_id, at, nbf, expire_at,
                pg_channel, pg_data)

  local res, err = self.connector:query(q)
  if not res then
    return nil, "could not insert invalidation row: " .. err
  end

  return true
end


function _M:select_interval(channels, min_at, max_at)
  local n_chans = #channels
  local p_chans = new_tab(n_chans, 0)
  local p_minat = self.connector:escape_literal(tonumber(fmt("%.3f", min_at)))
  local p_maxat = self.connector:escape_literal(tonumber(fmt("%.3f", max_at)))

  for i = 1, n_chans do
    p_chans[i] = self.connector:escape_literal(channels[i])
  end

  local query_template = fmt(SELECT_INTERVAL_QUERY,
                             concat(p_chans, ", "),
                             p_minat,
                             p_maxat,
                             self.page_size,
                             "%s")

  local page = 0

  return function()
    local offset = page * self.page_size
    local q = fmt(query_template, offset)

    local res, err = self.connector:query(q)
    if not res then
      return nil, err
    end

    local len = #res
    if len == 0 then
      return nil
    end

    for i = 1, len do
      local row = res[i]
      if row.nbf == null then
        row.nbf = nil
      end
    end

    page = page + 1

    return res, err, page
  end
end


function _M:truncate_events()
  return self.connector:query("TRUNCATE cluster_events")
end


return _M
