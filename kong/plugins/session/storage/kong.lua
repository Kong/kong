local setmetatable = setmetatable
local get_phase    = ngx.get_phase
local timer_at     = ngx.timer.at
local kong         = kong


local storage = {}


storage.__index = storage


function storage.new(session)
  return setmetatable({
    session     = session,
    encode      = session.encoder.encode,
    decode      = session.encoder.decode,
  }, storage)
end


local function load_session(id)
  return kong.db.sessions:select_by_session_id(id)
end


function storage:get(id)
  local cache_key = kong.db.sessions:cache_key(id)
  return kong.cache:get(cache_key, nil, load_session, id)
end


function storage:open(id)
  if get_phase() == "header_filter" then
    return
  end

  local row, err = self:get(id)
  if not row then
    return nil, err
  end

  return self.decode(row.data)
end


function storage:insert_session(id, data, ttl)
  return kong.db.sessions:insert({
    session_id = id,
    data       = data,
    expires    = self.session.now + ttl,
  }, { ttl = ttl })
end


function storage:update_session(id, params, ttl)
  return kong.db.sessions:update({ id = id }, params, { ttl = ttl })
end


function storage:save(id, ttl, data)
  local data = self.encode(data)
  if get_phase() == "header_filter" then
    timer_at(0, function()
      return self:insert_session(id, data, ttl)
    end)

    return true
  end

  return self:insert_session(id, data, ttl)
end


function storage:destroy(id)
  local row, err = self:get(id)
  if not row then
    return nil, err
  end

  return kong.db.sessions:delete({ id = row.id })
end


-- used by regenerate strategy to expire old sessions during renewal
function storage:ttl(id, ttl)
  if get_phase() == "header_filter" then
    timer_at(0, function()
      local row, err = self:get(id)
      if not row then
        return nil, err
      end

      return self:update_session(row.id, {
        session_id = row.session_id
      }, ttl)
    end)

    return true
  end

  local row, err = self:get(id)
  if not row then
    return nil, err
  end

  return self:update_session(row.id, {
    session_id = row.session_id
  }, ttl)
end


return storage
