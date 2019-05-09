local cjson = require "cjson.safe"


local ngx          = ngx
local type         = type
local time         = ngx.time
local shared       = ngx.shared
local cjson_encode = cjson.encode
local cjson_decode = cjson.decode


local _M = {}


--- Create new memory strategy object
-- @table opts Strategy options: contains 'dictionary_name' and 'ttl' fields
function _M.new(opts)
  local dict = shared[opts.dictionary_name]

  local self = {
    dict = dict,
    opts = opts,
  }

  return setmetatable(self, {
    __index = _M,
  })
end


--- Store a new request entity in the shared memory
-- @string key The request key
-- @table req_obj The request object, represented as a table containing
--   everything that needs to be cached
-- @int[opt] ttl The TTL for the request; if nil, use default TTL specified
--   at strategy instantiation time
function _M:store(key, req_obj, req_ttl)
  local ttl = req_ttl or self.opts.ttl

  if type(key) ~= "string" then
    return nil, "key must be a string"
  end

  -- encode request table representation as JSON
  local req_json = cjson_encode(req_obj)
  if not req_json then
    return nil, "could not encode request object"
  end

  local succ, err = self.dict:set(key, req_json, ttl)
  return succ and req_json or nil, err
end


--- Fetch a cached request
-- @string key The request key
-- @return Table representing the request
function _M:fetch(key)
  if type(key) ~= "string" then
    return nil, "key must be a string"
  end

  -- retrieve object from shared dict
  local req_json, err = self.dict:get(key)
  if not req_json then
    if not err then
      return nil, "request object not in cache"

    else
      return nil, err
    end
  end

  -- decode object from JSON to table
  local req_obj = cjson_decode(req_json)
  if not req_json then
    return nil, "could not decode request object"
  end

  return req_obj
end


--- Purge an entry from the request cache
-- @return true on success, nil plus error message otherwise
function _M:purge(key)
  if type(key) ~= "string" then
    return nil, "key must be a string"
  end

  self.dict:delete(key)
  return true
end


--- Reset TTL for a cached request
function _M:touch(key, req_ttl, timestamp)
  if type(key) ~= "string" then
    return nil, "key must be a string"
  end

  -- check if entry actually exists
  local req_json, err = self.dict:get(key)
  if not req_json then
    if not err then
      return nil, "request object not in cache"

    else
      return nil, err
    end
  end

  -- decode object from JSON to table
  local req_obj = cjson_decode(req_json)
  if not req_json then
    return nil, "could not decode request object"
  end

  -- refresh timestamp field
  req_obj.timestamp = timestamp or time()

  -- store it again to reset the TTL
  return _M:store(key, req_obj, req_ttl)
end


--- Marks all entries as expired and remove them from the memory
-- @param free_mem Boolean indicating whether to free the memory; if false,
--   entries will only be marked as expired
-- @return true on success, nil plus error message otherwise
function _M:flush(free_mem)
  -- mark all items as expired
  self.dict:flush_all()
  -- flush items from memory
  if free_mem then
    self.dict:flush_expired()
  end

  return true
end

return _M
