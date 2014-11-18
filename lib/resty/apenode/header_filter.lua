-- Copyright (C) Mashape, Inc.


local _M = { _VERSION    = '0.1' }


function _M.execute()
    ngx.log(ngx.INFO, "Header Filter")
end


return _M
