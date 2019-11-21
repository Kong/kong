local utils  = require "kong.tools.utils"


local fmt          = string.format
local type         = type
local null         = ngx.null
local error        = error
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
  %s,
  %s,
  CURRENT_TIMESTAMP(3) AT TIME ZONE 'UTC' + INTERVAL '%d second',
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
         EXTRACT(EPOCH FROM "nbf" AT TIME ZONE 'UTC') AS "nbf",
         EXTRACT(EPOCH FROM CURRENT_TIMESTAMP(3) AT TIME ZONE 'UTC') AS "now"
    FROM "cluster_events"
   WHERE "channel" IN (%s)
     AND "at" >  TO_TIMESTAMP(%s) AT TIME ZONE 'UTC'
     AND "at" <= %s
ORDER BY "at"
   LIMIT %s
  OFFSET %s
]]


local SERVER_TIME_QUERY = [[
SELECT EXTRACT(EPOCH FROM CURRENT_TIMESTAMP(3) AT TIME ZONE 'UTC') AS "now"
]]


local _M = {}


local mt = { __index = _M }


function _M.new(db, page_size, event_ttl)
  if type(page_size) ~= "number" then
    error("page_size must be a number", 2)
  end

  local self  = {
    connector = db.connector,
    page_size = page_size,
    event_ttl = event_ttl,
  }

  return setmetatable(self, mt)
end


function _M.should_use_polling()
  return true
end


function _M:insert(node_id, channel, at, data, delay)
  if at then
    at = fmt("TO_TIMESTAMP(%s) AT TIME ZONE 'UTC'",
             self.connector:escape_literal(tonumber(fmt("%.3f", at))))

  else
    at = "CURRENT_TIMESTAMP(3) AT TIME ZONE 'UTC'"
  end

  local nbf
  if delay then
    nbf = fmt("CURRENT_TIMESTAMP(3) AT TIME ZONE 'UTC' + INTERVAL '%d second'", delay)
  else
    nbf = "NULL"
  end

  local pg_id      = self.connector:escape_literal(utils.uuid())
  local pg_node_id = self.connector:escape_literal(node_id)
  local pg_channel = self.connector:escape_literal(channel)
  local pg_data    = self.connector:escape_literal(data)

  local q = fmt(INSERT_QUERY, pg_id, pg_node_id, at, nbf, self.event_ttl,
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

  for i = 1, n_chans do
    p_chans[i] = self.connector:escape_literal(channels[i])
  end

  p_chans = concat(p_chans, ", ")

  local p_minat = self.connector:escape_literal(tonumber(fmt("%.3f", min_at or 0)))
  local p_maxat
  if max_at then
    p_maxat = fmt("TO_TIMESTAMP(%s) AT TIME ZONE 'UTC'",
                  self.connector:escape_literal(tonumber(fmt("%.3f", max_at))))
  else
    p_maxat = "CURRENT_TIMESTAMP(3) AT TIME ZONE 'UTC'"
  end

  local query_template = fmt(SELECT_INTERVAL_QUERY, p_chans,
                                                    p_minat,
                                                    p_maxat,
                                                    self.page_size,
                                                    "%s")

  local page = 0
  local last_page
  return function()
    if last_page then
      return nil
    end

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
      if res[i].nbf == null then
        res[i].nbf = nil
      end
    end

    if len < self.page_size then
      last_page = true
    end

    page = page + 1

    return res, err, page
  end
end


function _M:truncate_events()
  return self.connector:query("TRUNCATE cluster_events")
end


function _M:server_time()
  local res, err = self.connector:query(SERVER_TIME_QUERY)
  if res then
    return res[1].now
  end

  return nil, err
end


return _M
