--[[
  Copyright (c) 2016. Adobe Systems Incorporated. All rights reserved.

    This file is licensed to you under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License is
    distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR RESPRESENTATIONS OF ANY KIND,
    either express or implied.  See the License for the specific language governing permissions and
    limitations under the License.

  ]]

--
-- This modules is a wrapper for the lua-resty-http (https://github.com/pintsized/lua-resty-http) library
-- exposing the "request" method to be compatible with the embedded http client (kong.plugins.aws-lambda.api-gateway.aws.httpclient.http)
-- User: ddascal
-- Date: 08/03/16
--

local _M = {}
local http = require "kong.plugins.aws-lambda.resty.http"

function _M:new(o)
    local o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function _M:request( req )
    local ok, code
    local httpc = http.new()
    httpc:set_timeout(req.timeout or 60000)

    local res, err = httpc:request_uri(req.scheme .. "://" .. req.host .. ":" .. req.port, {
        path = req.url,
        method = req.method,
        body = req.body,
        headers = req.headers,
        ssl_verify = false
    })

    if not res then
        ngx.log(ngx.ERR, "failed to make request: ", err)
        return false, err, nil, err, nil
    end

    return ok, res.status, res.headers, res.status, res.body
end

return _M

