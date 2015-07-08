local iputils = require "resty.iputils"

local _M = {}

function _M.execute()
  iputils.enable_lrucache()
end

return _M
