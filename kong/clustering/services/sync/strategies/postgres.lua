local _M = {}
local _MT = { __index = _M }


local cjson = require("cjson.safe")
local buffer = require("string.buffer")


local string_format = string.format
local cjson_encode = cjson.encode
local ngx_null = ngx.null
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_DEBUG = ngx.DEBUG


local CLEANUP_VERSION_COUNT = 100
local CLEANUP_TIME_DELAY = 3600  -- 1 hour


function _M.new(db)
  local self = {
    connector = db.connector,
  }

  return setmetatable(self, _MT)
end


local PURGE_QUERY = [[
  DELETE FROM clustering_sync_version
  WHERE "version" < (
      SELECT MAX("version") - %d
      FROM clustering_sync_version
  );
]]


function _M:init_worker()
  local function cleanup_handler(premature)
    if premature then
      ngx_log(ngx_DEBUG, "[incremental] worker exiting, killing incremental cleanup timer")

      return
    end

    local res, err = self.connector:query(string_format(PURGE_QUERY, CLEANUP_VERSION_COUNT))
    if not res then
      ngx_log(ngx_ERR,
              "[incremental] unable to purge old data from incremental delta table, err: ",
              err)

      return
    end

    ngx_log(ngx_DEBUG,
            "[incremental] successfully purged old data from incremental delta table")
  end

  assert(ngx.timer.every(CLEANUP_TIME_DELAY, cleanup_handler))
end


local NEW_VERSION_QUERY = [[
  DO $$
  DECLARE
    new_version integer;
  BEGIN
    INSERT INTO clustering_sync_version DEFAULT VALUES RETURNING version INTO new_version;
    INSERT INTO clustering_sync_delta (version, type, pk, ws_id, row) VALUES %s;
  END $$;
]]


-- deltas: {
--   { type = "service", "pk" = "d78eb00f-8702-4d6a-bfd9-e005f904ae3e", "ws_id" = "73478cf6-964f-412d-b1c4-8ac88d9e85e9", row = "JSON", }
--   { type = "route", "pk" = "0a5bac5c-b795-4981-95d2-919ba3390b7e", "ws_id" = "73478cf6-964f-412d-b1c4-8ac88d9e85e9", row = "JSON", }
-- }
function _M:insert_delta(deltas)
  local buf = buffer.new()
  for _, d in ipairs(deltas) do
    buf:putf("(new_version, %s, %s, %s, %s)",
             self.connector:escape_literal(d.type),
             self.connector:escape_literal(d.pk),
             self.connector:escape_literal(d.ws_id or kong.default_workspace),
             self.connector:escape_literal(cjson_encode(d.row)))
  end

  local sql = string_format(NEW_VERSION_QUERY, buf:get())

  return self.connector:query(sql)
end


function _M:get_latest_version()
  local sql = "SELECT MAX(version) FROM clustering_sync_version"

  local res, err = self.connector:query(sql)
  if not res then
    return nil, err
  end

  local ver = res[1] and res[1].max
  if ver == ngx_null then
    return 0
  end

  return ver
end


function _M:get_delta(version)
  local sql = "SELECT * FROM clustering_sync_delta" ..
              " WHERE version > " ..  self.connector:escape_literal(version) ..
              " ORDER BY version ASC"
  return self.connector:query(sql)
end


function _M:begin_txn()
  return self.connector:query("BEGIN;")
end


function _M:commit_txn()
  return self.connector:query("COMMIT;")
end


function _M:cancel_txn()
  -- we will close the connection, not execute 'ROLLBACK'
  return self.connector:close()
end


return _M
