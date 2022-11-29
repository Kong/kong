local _M = {}
--local _MT = { __index = _M, }

local constants = require "kong.constants"
local txn = require "resty.lmdb.transaction"

local ipairs = ipairs
local tostring = tostring
local max = math.max
local min = math.min

local exiting = ngx.worker.exiting
local unmarshall = require("kong.db.declarative.marshaller").unmarshall

local is_http_subsystem = ngx.config.subsystem == "http"

local DECLARATIVE_HASH_KEY = constants.DECLARATIVE_HASH_KEY


local function load_into_cache(entries)
  ngx.log(ngx.ERR, "xxx count = ", #entries)

  --local is_incremental = entries[1].event ~= nil
  local is_full_sync = entries[1].event == nil

  local default_ws

  local t = txn.begin(#entries)

  -- full sync will drop all data
  if is_full_sync then
    t:db_drop(false)
  end

  local latest_revision = 0
  for _, entry in ipairs(entries) do
    latest_revision = max(latest_revision, entry.revision)
    ngx.log(ngx.ERR, "xxx revision = ", entry.revision, " key = ", entry.key)

    if entry.event and entry.event == 3 then
      -- incremental delete
      t:set(entry.key, nil)

    else
      t:set(entry.key, entry.value)
    end

    -- find the default workspace id
    if not default_ws then
      if entry.key == "workspaces:default:::::" then
        local obj = unmarshall(entry.value)
        default_ws = obj.id
        ngx.log(ngx.ERR, "xxx find default_ws = ", default_ws)
      end
    end
  end -- entries

  -- we can get current_version from lmdb
  t:set(DECLARATIVE_HASH_KEY, tostring(latest_revision))

  local ok, err = t:commit()
  if not ok then
    return nil, err
  end

  ngx.log(ngx.ERR, "xxx latest_revision = ", latest_revision)

  --current_version = latest_revision

  --kong.default_workspace = default_workspace

  kong.core_cache:purge()
  kong.cache:purge()

  if not default_ws then
    default_ws = kong.default_workspace
  end

  return true, nil, default_ws
end

local function load_into_cache_with_events_no_lock(entries)
  if exiting() then
    return nil, "exiting"
  end
  --ngx.log(ngx.ERR, "xxx load_into_cache_with_events_no_lock = ", #entries)

  local ok, err, default_ws = load_into_cache(entries)
  if not ok then
    if err:find("MDB_MAP_FULL", nil, true) then
      return nil, "map full"

    else
      return nil, err
    end
  end

  local worker_events = kong.worker_events

  --local default_ws = "6af4a340-fab2-4ed8-953d-21b852133fa6"

  local reconfigure_data = {
    default_ws,
    -- other hash is nil, trigger router/balancer rebuild
  }

  -- go to runloop/handler reconfigure_handler
  ok, err = worker_events.post("declarative", "reconfigure", reconfigure_data)
  if ok ~= "done" then
    return nil, "failed to broadcast reconfigure event: " .. (err or ok)
  end

  -- TODO: send to stream subsystem
  if is_http_subsystem and #kong.configuration.stream_listeners > 0 then
    -- update stream if necessary
    ngx.log(ngx.ERR, "xxx update stream if necessary = ")
  end


  if exiting() then
    return nil, "exiting"
  end

  return true
end

-- TODO: change to another names
local DECLARATIVE_LOCK_TTL = 60
local DECLARATIVE_RETRY_TTL_MAX = 10
local DECLARATIVE_LOCK_KEY = "declarative:lock"

-- copied from declarative/init.lua
function _M.load_into_cache_with_events(entries)
  --ngx.log(ngx.ERR, "xxx load_into_cache_with_events = ", #entries)
  local kong_shm = ngx.shared.kong

  local ok, err = kong_shm:add(DECLARATIVE_LOCK_KEY, 0, DECLARATIVE_LOCK_TTL)
  if not ok then
    if err == "exists" then
      local ttl = min(kong_shm:ttl(DECLARATIVE_LOCK_KEY), DECLARATIVE_RETRY_TTL_MAX)
      return nil, "busy", ttl
    end

    kong_shm:delete(DECLARATIVE_LOCK_KEY)
    return nil, err
  end

  ok, err = load_into_cache_with_events_no_lock(entries)
  kong_shm:delete(DECLARATIVE_LOCK_KEY)

  return ok, err
end

return _M
