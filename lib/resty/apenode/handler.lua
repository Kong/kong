-- Copyright (C) Mashape, Inc.


local _M = { _VERSION    = '0.1' }


function _M.init()
    ngx.log(ngx.INFO, "Init")
end


function _M.access()
    ngx.log(ngx.INFO, "Access")

    local querystring = ngx.encode_args(ngx.req.get_uri_args());
    ngx.var.backend_url = "https://www.mashape.com" .. ngx.var.uri .. "?" .. querystring
end


function _M.content()
    ngx.log(ngx.INFO, "Content")
end


function _M.rewrite()
    ngx.log(ngx.INFO, "Rewrite")
end


function _M.header_filter()
    ngx.log(ngx.INFO, "Header Filter")
end


function _M.body_filter()
    ngx.log(ngx.INFO, "Body Filter")
end


function _M.log()
    ngx.log(ngx.INFO, "Log")
end


return _M
