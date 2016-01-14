local iputils = require "resty.iputils"

local _M = {}

function _M.execute()
  local ok, err = iputils.enable_lrucache()
  if not ok then
    ngx.log(ngx.ERR, "[ip-restriction] Could not enable lrucache: ", err)
  end
end

return _M
