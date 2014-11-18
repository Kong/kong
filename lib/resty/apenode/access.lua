-- Copyright (C) Mashape, Inc.


local _M = { _VERSION    = '0.1' }


function _M.execute()
    ngx.log(ngx.INFO, "Access")

    local querystring = ngx.encode_args(ngx.req.get_uri_args());
    ngx.var.backend_url = "https://www.mashape.com" .. ngx.var.uri .. "?" .. querystring
end


return _M
