local cache = require "kong.tools.database_cache"
local pl_tablex = require "pl.tablex"

local _M = {}

local INDEX = "bot_detection_index"

function _M.set(key, value)
  cache.set(cache.bot_detection_key(key), value)
  local index_keys = cache.get(INDEX)
  if index_keys ~= nil then 
    index_keys = pl_tablex.deepcopy(index_keys)
  else
    index_keys = {} 
  end
  index_keys[#index_keys+1] = key
  cache.set(INDEX, index_keys)
end

function _M.get(key)
  return cache.get(cache.bot_detection_key(key))
end

function _M.reset()
  local index_keys = cache.get(INDEX)
  if index_keys ~= nil then
    for _, key in ipairs(index_keys) do
      cache.delete(cache.bot_detection_key(key))
    end
    cache.delete(INDEX)
  end
end

return _M