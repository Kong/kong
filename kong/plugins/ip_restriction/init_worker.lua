local _M = {}

function _M.execute()
  local iputils = require "resty.iputils"
  iputils.enable_lrucache()
end

return _M
