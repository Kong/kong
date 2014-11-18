-- Copyright (C) Mashape, Inc.


local _M = { _VERSION    = '0.13' }


function _M.log()
    ngx.print("Hello World")
end


return _M