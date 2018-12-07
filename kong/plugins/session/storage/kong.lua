local singletons   = require "kong.singletons"
local concat       = table.concat
local tonumber     = tonumber
local setmetatable = setmetatable
local floor        = math.floor
local now          = ngx.now

local kong_storage = {}

kong_storage.__index = kong_storage

function kong_storage.new(config)
  return setmetatable({
    dao         = singletons.dao,
    encode      = config.encoder.encode,
    decode      = config.encoder.decode,
    delimiter   = config.cookie.delimiter,
    lifetime    = config.cookie_lifetime,
  }, kong_storage)
end


function kong_storage:get(k)
  local s, err = self.dao.sessions:find({ id = k })

  if err then
    ngx.log(ngx.ERR, "Error finding session:", err)
  end

  return s, err
end


function kong_storage:cookie(c)
  local r, d = {}, self.delimiter
  local i, p, s, e = 1, 1, c:find(d, 1, true)
  while s do
      if i > 2 then
          return nil
      end
      r[i] = c:sub(p, e - 1)
      i, p = i + 1, e + 1
      s, e = c:find(d, p, true)
  end
  if i ~= 3 then
      return nil
  end
  r[3] = c:sub(p)
  return r
end


function kong_storage:open(cookie, lifetime)
  local c = self:cookie(cookie)

  if c and c[1] and c[2] and c[3] then
    local id, expires, hmac = self.decode(c[1]), tonumber(c[2]), self.decode(c[3])
    local data

    if ngx.get_phase() ~= 'header_filter' then
      local key = c[1]
      local db_s = self:get(key)
      if db_s then
        data = self.decode(db_s.data)
      end
    end
    
    return id, expires, data, hmac
  end

  return nil, "invalid"
end


function kong_storage:save(id, expires, data, hmac)
  local life, key = floor(expires - now()), self.encode(id)
  local value = concat({key, expires, self.encode(hmac)}, self.delimiter)

  if life > 0 then
    ngx.timer.at(0, function()
      local s = self:get(key)
      
      local err, _
      
      if s then
        _, err = self.dao.sessions:update({ id = s.id }, {
          data = self.encode(data),
          expires = expires,
        }, { ttl = self.lifetime })
      else
        _, err = self.dao.sessions:insert({
          id = key,
          data = self.encode(data),
          expires = expires,
        }, { ttl = self.lifetime })
      end

      if err then
        ngx.log(ngx.ERR, "Error inserting session: ", err)
      end
    end)

    return value
  end

  return nil, "expired" 
end


function kong_storage:destroy(id)
  local db_s = self:get(id)

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
