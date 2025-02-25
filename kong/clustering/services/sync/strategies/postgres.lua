local _M = {}
local _MT = { __index = _M }


local type = type
local sub = string.sub
local fmt = string.format
local ngx_null = ngx.null


-- version string should look like: "v02_0000"
local VER_PREFIX = "v02_"
local VER_PREFIX_LEN = #VER_PREFIX
local VER_DIGITS = 28
-- equivalent to "v02_" .. "%028x"
local VERSION_FMT = VER_PREFIX .. "%0" .. VER_DIGITS .. "x"


function _M.new(db)
  local self = {
    connector = db.connector,
  }

  return setmetatable(self, _MT)
end


-- reserved for future
function _M:init_worker()
end


local NEW_VERSION_QUERY = [[
  DO $$
  DECLARE
    new_version integer;
  BEGIN
    INSERT INTO clustering_sync_version DEFAULT VALUES RETURNING version INTO new_version;
  END $$;
]]


function _M:insert_delta()
  return self.connector:query(NEW_VERSION_QUERY)
end


function _M:get_latest_version()
  local sql = "SELECT MAX(version) FROM clustering_sync_version"

  local res, err = self.connector:query(sql, "read")
  if not res then
    return nil, err
  end

  local ver = res[1] and res[1].max
  if ver == ngx_null then
    return fmt(VERSION_FMT, 0)
  end

  return fmt(VERSION_FMT, ver)
end


function _M:is_valid_version(str)
  if type(str) ~= "string" then
    return false
  end

  if #str ~= VER_PREFIX_LEN + VER_DIGITS then
    return false
  end

  -- | v02_xxxxxxxxxxxxxxxxxxxxxxxxxx |
  --   |--|
  -- Is starts with "v02_"?
  if sub(str, 1, VER_PREFIX_LEN) ~= VER_PREFIX then
    return false
  end

  -- | v02_xxxxxxxxxxxxxxxxxxxxxxxxxx |
  --       |------------------------|
  -- Is the rest a valid hex number?
  if not tonumber(sub(str, VER_PREFIX_LEN + 1), 16) then
    return false
  end

  return true
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
