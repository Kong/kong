-- Kinesis Client


local AwsService = require "kong.plugins.aws-lambda.api-gateway.aws.AwsService"
local cjson = require "cjson"
local error = error

local _M = AwsService:new({ ___super = true })
local super = {
    instance = _M,
    constructor = _M.constructor
}

function _M.new(self, o)
    ngx.log(ngx.DEBUG, "LambdaService() o=", tostring(o))
    local o = o or {}
    o.aws_service = "lambda"
    -- aws_service_name is used in the X-Amz-Target Header: i.e Kinesis_20131202.ListStreams
    o.aws_service_name = "Lambda"

    super.constructor(_M, o)

    setmetatable(o, self)
    self.__index = self
    return o
end

--- API: http://docs.aws.amazon.com/lambda/latest/dg/API_ListFunctions.html
--  GET /2015-03-31/functions/?Marker=Marker&MaxItems=MaxItems HTTP/1.1
function _M:listFunctions(marker, maxItems)
    local path = "/2015-03-31/functions"
    local arguments = {
        Marker = marker,
        MaxItems = maxItems
    }


    -- actionName, arguments, path, http_method, useSSL, timeout, contentType
    local ok, code, headers, status, body = self:performAction("ListFunctions", arguments, path, "GET", true, 60000)

    if (code == ngx.HTTP_OK and body ~= nil) then
        return cjson.decode(body), code, headers, status, body
    end
    return nil, code, headers, status, body
end

-- API: http://docs.aws.amazon.com/lambda/latest/dg/API_Invoke.html
--
function _M:invoke(functionName, payload, clientContext, invocationType, logType)
    assert(functionName ~= nil, "Please provide a valid functionName.")
    local invocationType = invocationType or "RequestResponse"
    local logType = logType or "None"
    local clientContext = clientContext
    if (clientContext ~= nil) then
        clientContext = ngx.encode_base64(clientContext) -- The ClientContext JSON must be base64-encoded.
    end


    --    POST /2015-03-31/functions/FunctionName/invocations HTTP/1.1
    --    X-Amz-Client-Context: ClientContext
    --    X-Amz-Invocation-Type: InvocationType
    --    X-Amz-Log-Type: LogType
    --
    --    Payload
    local path = "/2015-03-31/functions/" .. ngx.escape_uri(functionName) .. "/invocations"
    local extra_headers = {
       ["X-Amz-Client-Context"] = clientContext,
       ["X-Amz-Invocation-Type"] = invocationType,
       ["X-Amz-Log-Type"] = logType
    }

    -- actionName, arguments, path, http_method, useSSL, timeout, contentType
    local ok, code, headers, status, body = self:performAction("Invoke", payload, path, "POST", true, 60000, "application/x-amz-json-1.1", extra_headers)

    if (code == ngx.HTTP_OK and body ~= nil) then
        return {}, code, headers, status, body
    end
    return nil, code, headers, status, body
end


return _M

