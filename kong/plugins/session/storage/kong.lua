local singletons   = require "kong.singletons"
local concat       = table.concat
local tonumber     = tonumber
local setmetatable = setmetatable

local kong_storage = {}

kong_storage.__index = kong_storage

function kong_storage.new(config)
  return setmetatable({
      dao         = singletons.dao,
      prefix      = "session:cache",
      encode      = config.encoder.encode,
      decode      = config.encoder.decode,
      delimiter   = config.cookie.delimiter
  }, kong_storage)
end


function kong_storage:key(id)
  return self.encode(id)
end


function kong_storage:get(k)
  local sessions, err = self.dao.sessions:find_all({
    sid = k,
  })

  if err then
    ngx.log(ngx.ERR, "Error finding session:", err)
  end

  if not next(sessions) then
    return nil, err
  end

  return sessions[1]
end


function kong_storage:cookie(c)
  local r, d = {}, self.delimiter
  local i, p, s, e = 1, 1, c:find(d, 1, true)
  while s do
    if i > 3 then
        return nil
    end
    r[i] = c:sub(p, e - 1)
    i, p = i + 1, e + 1
    s, e = c:find(d, p, true)
  end
  if i ~= 4 then
      return nil
  end
  r[4] = c:sub(p)
  return r
end


function kong_storage:open(cookie)
  local c = self:cookie(cookie)

  if c and c[1] and c[2] and c[3] and c[4] then
    local id, expires, d, hmac = self.decode(c[1]), tonumber(c[2]), 
                                 self.decode(c[3]), self.decode(c[4])
    local key = self:key(id)
    local data = d

    if ngx.get_phase() ~= 'header_filter' then
      local db_s = self:get(key)
      data = (db_s and self.decode(db_s.data)) or d
    end
    
    return id, expires, data, hmac
  end

  return nil, "invalid"
end


function kong_storage:save(id, expires, data, hmac)
  local value = concat({self:key(id), expires, self.encode(data),
                        self.encode(hmac)}, self.delimiter)
  
  ngx.timer.at(0, function()
    local key = self:key(id)
    local s = self:get(key)
    local err, _
    
    if s then
      _, err = self.dao.sessions:update({ id = s.id, }, {
        data = self.encode(data),
        expires = expires,
      })
    else
      _, err = self.dao.sessions:insert({
        sid = self:key(id),
        data = self.encode(data),
        expires = expires,
      })
    end

    if err then
      ngx.log(ngx.ERR, "Error inserting session: ", err)
    end
  end)

  return value
end


function kong_storage:destroy(id)
  local db_s = self:get(self:key(id))

  if not db_s then
    return
  end
  
  local _, err = self.dao.sessions:delete({
    id = db_s.id
  })

  if err then
    ngx.log(ngx.ERR, "Error deleting session: ", err)
  end
end

return kong_storage
