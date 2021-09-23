local marshaller = require("kong.cache.lmdb.marshaller")


local marshall = marshaller.marshall
local unmarshall = marshaller.unmarshall
local type    = type
local pairs   = pairs
local error   = error
local max     = math.max
local ngx     = ngx
local ngx_log = ngx.log
local ERR     = ngx.ERR
local NOTICE  = ngx.NOTICE
local DEBUG   = ngx.DEBUG


--[[
Hypothesis
----------

Item size:        1024 bytes
Max memory limit: 500 MiBs

LRU size must be: (500 * 2^20) / 1024 = 512000
Floored: 500.000 items should be a good default
--]]
local LRU_SIZE = 5e5


local _init = {}


local function log(lvl, ...)
  return ngx_log(lvl, "[DB cache] ", ...)
end


local _M = {}
local mt = { __index = _M }


function _M.new(lmdb)
  local self = {
    lmdb = lmdb,
  }

  return setmetatable(self, mt)
end


--function _M:get_page(shadow)
--  if #self.mlcaches == 2 and shadow then
--    return self.page == 2 and 1 or 2
--  end
--
--  return self.page or 1
--end


function _M:get(key)
  if type(key) ~= "string" then
    error("key must be a string", 2)
  end

  local v, err = self.lmdb:get(key)
  if err then
    return nil, "failed to get from node cache: " .. err
  end

  return v and unmarshall(v) or nil
end


--function _M:get_bulk(bulk, opts)
--  if type(bulk) ~= "table" then
--    error("bulk must be a table", 2)
--  end
--
--  if opts ~= nil and type(opts) ~= "table" then
--    error("opts must be a table", 2)
--  end
--
--  local page = self:get_page((opts or {}).shadow)
--  local res, err = self.mlcaches[page]:get_bulk(bulk, opts)
--  if err then
--    return nil, "failed to get_bulk from node cache: " .. err
--  end
--
--  return res
--end


function _M:safe_set(key, value)
  local str_marshalled, err = marshall(value)
  if err then
    return nil, err
  end

  return self.lmdb:set(key, str_marshalled)
end


return _M
