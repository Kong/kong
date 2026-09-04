-- kong.plugin.acme.storage.kong implements the lua-resty-acme
-- storage adapter interface by using kong's db as backend

local table_insert = table.insert

local _M = {}
local mt = {__index = _M}

function _M.new(_)
  local self = setmetatable({
    dao = kong.db.acme_storage,
  }, mt)
  return self
end

function _M:add(k, v, ttl)
  local vget, err = self:get(k)
  if err then
    return "error getting key " .. err
  end
  -- check first to make testing happier. we will still fail out
  -- if insert failed
  if vget then
    return "exists"
  end
  local _, err = self.dao:insert({
    key = k,
    value = v,
  }, { ttl = ttl })
  return err
end

function _M:set(k, v, ttl)
  local _, err = self.dao:upsert_by_key(k, {
    value = v,
  }, { ttl = ttl })
  return err
end

local function db_read(dao, k)
  local row, err = dao:select_by_key(k)
  if err then
    return nil, err
  elseif not row then
    return nil, nil
  end
  return row, nil
end

function _M:delete(k)
  local v, err = db_read(self.dao, k)
  if err then
    return err
  elseif not v then
    return
  end

  local _, err = self.dao:delete(v)
  return err
end

function _M:get(k)
  local row, err = db_read(self.dao, k)
  if err then
    return nil, err
  end
  return row and row.value, nil
end

local empty_table = {}
function _M:list(prefix)
  local prefix_length
  if prefix then
    prefix_length = #prefix
  end
  local rows, err, _, offset
  local keys = {}
  while true do
    rows, err, _, offset = self.dao:page(100, offset)
    if err then
      return empty_table, err
    end
    for _, row in ipairs(rows) do
      if not prefix or row['key']:sub(1, prefix_length) == prefix then
        table_insert(keys, row['key'])
      end
    end
    if not offset then
      break
    end
  end
  return keys
end

return _M
