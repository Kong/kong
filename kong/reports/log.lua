local cache = require "kong.tools.database_cache"

local _M = {}

function _M.execute(conf)
  cache.incr(cache.requests_key(), 1)
end

return _M