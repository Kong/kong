local get_phase = ngx.get_phase
local timer_at = ngx.timer.at
local kong = kong


local PK = {
  id = "",
}

local TTL = {
  ttl = 0,
}

local DATA = {
  session_id = "",
  data = "",
  expires = 0,
}

local STALE_DATA = {
  expires = 0,
}


local storage = {}


storage.__index = storage


local function load_session_from_db(key)
  return kong.db.sessions:select_by_session_id(key)
end


local function load_session_from_cache(key)
  local cache_key = kong.db.sessions:cache_key(key)
  return kong.cache:get(cache_key, nil, load_session_from_db, key)
end


local function insert_session(key, value, ttl, current_time, old_key, stale_ttl, remember)
  DATA.session_id = key
  DATA.data = value
  DATA.expires = current_time + ttl

  TTL.ttl = ttl

  local insert_ok, insert_err = kong.db.sessions:insert(DATA, TTL)
  if not old_key then
    return insert_ok, insert_err
  end

  local old_row, err = load_session_from_cache(old_key)
  if err then
    kong.log.notice(err)

  elseif old_row then
    PK.id = old_row.id
    if remember then
      local ok, err = kong.db.sessions:delete(PK)
      if not ok then
        if err then
          kong.log.notice(err)
        else
          kong.log.notice("unable to delete session data")
        end
      end

    else
      STALE_DATA.expires = current_time + stale_ttl
      TTL.ttl = stale_ttl
      local ok, err = kong.db.sessions:update(PK, STALE_DATA, TTL)
      if not ok then
        if err then
          kong.log.notice(err)
        else
          kong.log.notice("unable update session ttl")
        end
      end
    end
  end

  return insert_ok, insert_err
end


local function insert_session_timer(premature, ...)
  if premature then
    return
  end

  local ok, err = insert_session(...)
  if not ok then
    if err then
      kong.log.notice(err)
    else
      kong.log.warn("unable to insert session")
    end
  end
end


function storage:set(name, key, value, ttl, current_time, old_key, stale_ttl, metadata, remember)
  if get_phase() == "header_filter" then
    timer_at(0, insert_session_timer, key, value, ttl, current_time, old_key, stale_ttl, remember)
    return true
  end

  return insert_session(key, value, ttl, current_time, old_key, stale_ttl, remember)
end


function storage:get(name, key, current_time)
  if get_phase() == "header_filter" then
    return
  end

  local row, err = load_session_from_cache(key)
  if not row then
    return nil, err
  end

  return row.data
end


function storage:delete(name, key, current_time, metadata)
  local row, err = load_session_from_cache(key)
  if not row then
    return nil, err
  end

  PK.id = row.id

  return kong.db.sessions:delete(PK)
end


return storage
