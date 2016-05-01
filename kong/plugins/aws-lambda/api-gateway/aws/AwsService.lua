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

--- Base Class for working with AWS Services.
-- It's responsible for making API Requests to most of the AWS Services
--
-- Created by IntelliJ IDEA.
-- User: ddascal
-- Date: 24/11/14
-- Time: 18:46
--

local _M = { _VERSION = '0.01' }

local setmetatable = setmetatable
local error = error
local debug_mode = ngx.config.debug
local http = require"kong.plugins.aws-lambda.api-gateway.aws.httpclient.http"
local http_resty = require"kong.plugins.aws-lambda.api-gateway.aws.httpclient.restyhttp"
local AWSV4S = require"kong.plugins.aws-lambda.api-gateway.aws.AwsV4Signature"
local IamCredentials = require"kong.plugins.aws-lambda.api-gateway.aws.AWSIAMCredentials"
local cjson = require"cjson"

local http_client = http:new()
local http_client_resty = http_resty:new()

local function tableToString(table_ref)
    local s = ""
    local o = table_ref or {}
    for k, v in pairs(o) do
        s = s .. ", " .. k .. "=" .. tostring(v)
    end
    return s
end

--- Loads a lua gracefully. If the module doesn't exist the exception is caught, logged and the execution continues
-- @param module path to the module to be loaded
--
local function loadrequire(module)
    ngx.log(ngx.DEBUG, "Loading module [" .. tostring(module) .. "]")
    local function requiref(module)
        require(module)
    end

    local res = pcall(requiref, module)
    if not (res) then
        ngx.log(ngx.WARN, "Could not load module [", module, "].")
        return nil
    end
    return require(module)
end

---
-- @param o object containing info about the AWS Service and Credentials or IAM User to use
-- o.aws_region                     - required. AWS Region
-- o.aws_service                    - required. the AWS Service to call
-- o.aws_credentials                -  An object defining the credentials provider.
--          i.e. for IAM Credentials
--            aws_credentials = {
--                provider = "kong.plugins.aws-lambda.api-gateway.aws.AWSIAMCredentials",
--                shared_cache_dict = "my_dict",
--                security_credentials_host = "169.254.169.254",
--                security_credentials_port = "80"
--            }
--         i.e. for STS Credentials
--            aws_credentials = {
--                provider = "kong.plugins.aws-lambda.api-gateway.aws.AWSSTSCredentials",
--                role_ARN = "roleA",
--                role_session_name = "sessionB",
--                shared_cache_dict = "my_dict",
--                iam_security_credentials_host = "169.254.169.254",
--                iam_security_credentials_port = "80"
--         }
--        i.e. for Basic Credentials with access_key and secret:
--            aws_credentials = {
--                provider = "kong.plugins.aws-lambda.api-gateway.aws.AWSBasicCredentials",
--                access_key = ngx.var.aws_access_key,
--                secret_key = ngx.var.aws_secret_key
--            }
-- o.aws_secret_key  - deprecated. Use AWSBasicCredentials instead.
-- o.aws_access_key  - deprecated. Use AWSBasicCredentials instead.
-- o.security_credentials_host - optional. the AWS URL to read security credentials from and figure out the iam_user
-- o.security_credentials_port - optional. the port used when connecting to security_credentials_host
-- o.shared_cache_dict - optional. AWSIAMCredentials uses it to store IAM Credentials.
--
-- NOTE: class inheirtance inspired from: http://www.lua.org/pil/16.2.html
function _M:new(o)
    ngx.log(ngx.DEBUG, "AwsService() supercls=", tostring(o.___super))
    local o = o or {}
    setmetatable(o, self)
    self.__index = self
    if not o.___super then
        self:constructor(o)
    end

    return o
end

function _M:constructor(o)
    ngx.log(ngx.DEBUG, "AwsService() constructor ")
    local s = tableToString(o)
    ngx.log(ngx.DEBUG, "init object=" .. s)
    self:throwIfInitParamsInvalid(o)
    self.aws_credentials_provider = self:getCredentialsProvider(o)
end

function _M:throwIfInitParamsInvalid(o)
    if (o == nil) then
        error("Could not initialize. Missing init object. Please configure the AWS Service properly.")
    end


    local service = o.aws_service or ""
    if service == "" then
        error("aws_service is missing. Please provide one.")
    end

    local region = o.aws_region or ""
    if region == "" then
        error("aws_region is missing. Please provide one.")
    end
end

--- Returns the credentials provider to be used for authenticating with AWS.
--    If 'aws_credentials' init object is not set this method will try to guess one provider automatically
--    If 'aws_secret_key' and 'aws_access_key' is provided then AWSBasicCredentials is used,
--    else AWSIAMCredentials is used.
function _M:getCredentialsProvider(init_object)
    local secret = init_object.aws_secret_key or ""
    local key = init_object.aws_access_key or ""

    -- init credentials provider
    if (init_object.aws_credentials == nil) then
        ngx.log(ngx.DEBUG, "Missing 'aws_credentials' init option; will try to guess one.")
        -- assume it's the BasicCredentials first
        init_object.aws_credentials = {
            provider = "kong.plugins.aws-lambda.api-gateway.aws.AWSBasicCredentials",
            access_key = init_object.aws_access_key,
            secret_key = init_object.aws_secret_key
        }

        if (key == "" or secret == "") then
            ngx.log(ngx.DEBUG, "Using AWSIAMCredentials as 'aws_access_key' or 'aws_secret_key' were not provided.")
            init_object.aws_credentials = {
                provider = "kong.plugins.aws-lambda.api-gateway.aws.AWSIAMCredentials",
                shared_cache_dict = init_object.shared_cache_dict,
                security_credentials_host = init_object.security_credentials_host,
                security_credentials_port = init_object.security_credentials_port
            }
        end
    end

    ngx.log(ngx.DEBUG, "Initializing '", tostring(init_object.aws_credentials.provider), "' credentials provider for aws service=", tostring(init_object.aws_service))
    local credentialsCls = loadrequire(init_object.aws_credentials.provider)
    if (credentialsCls == nil) then
        ngx.log(ngx.WARN, "Invalid credentials provider:", tostring(init_object.aws_credentials.provider))
    end
    local credentialsProviderInstance = credentialsCls:new(init_object.aws_credentials)
    ngx.log(ngx.DEBUG, "Initialized security provider '", tostring(init_object.aws_credentials.provider), "' with options:", tableToString(init_object.aws_credentials))
    return credentialsProviderInstance
end


function _M:debug(...)
    if debug_mode then
        ngx.log(ngx.DEBUG, "AwsService: ", ...)
    end
end

function _M:getHttpClient()
--    return http_client -- the original http_client which will be deprecated and removed soon
    -- by default use the new http client that uses resty.http module
    return http_client_resty
end

function _M:getAWSHost()
    return self.aws_service .. "." .. self.aws_region .. ".amazonaws.com"
end

function _M:getCredentials()
    local key, secret, token, date, timestamp = self.aws_credentials_provider:getSecurityCredentials()
    local return_obj = {
        aws_access_key = key,
        aws_secret_key = secret,
        token = token
    }
    ngx.log(ngx.DEBUG, tostring(self.aws_service) .. " uses credentials from:" .. tostring(self.aws_credentials_provider.provider) .. " ->" .. return_obj.aws_access_key, " >> ", return_obj.aws_secret_key, " >> ", return_obj.token)
    return return_obj
end

function _M:getAuthorizationHeader(http_method, path, uri_args, body)
    local credentials = self:getCredentials()
    credentials.aws_region = self.aws_region
    credentials.aws_service = self.aws_service
    local awsAuth = AWSV4S:new(credentials)
    local authorization = awsAuth:getAuthorizationHeader(http_method,
        path, -- "/"
        uri_args, -- ngx.req.get_uri_args()
        body)
    return authorization, awsAuth, credentials.token
end

---
-- Hook to overwrite the request object before sending the request through to AWS
-- By default it returns the same object
-- @param object request object
--
function _M:getRequestObject(object)
    return object
end

function _M:getRequestArguments(actionName, parameters)
    local urlencoded_args = "Action=" .. actionName
    if parameters ~= nil then
        for key, value in pairs(parameters) do
            local proper_val = ngx.re.gsub(tostring(value), "&", "%26", "ijo")
            urlencoded_args = urlencoded_args .. "&" .. key .. "=" .. (proper_val or "")
        end
    end
    return urlencoded_args
end

---
-- Generic function used to call any AWS Service.
-- NOTE: All methods use AWS V4 signature, so this should be compatible with all the new AWS services.
-- More info: http://docs.aws.amazon.com/kms/latest/APIReference/CommonParameters.html
--
-- @param actionName Name of the AWS Action. i.e. GenerateDataKey
-- @param arguments Extra arguments needed for the action
-- @param path AWS Path. Default value is "/"
-- @param http_method Request HTTP Method. Default value is "GET"
-- @param useSSL Call using HTTPS or HTTP. Default value is "HTTP"
-- @param contentType Specifies how to deliver the content to the AWS Service.
--         Possible values are:   "application/x-amz-json-1.1" or "application/x-www-form-urlencoded"
-- @param extra_headers Any extra headers to be added to the request for the AWS Service
--
function _M:performAction(actionName, arguments, path, http_method, useSSL, timeout, contentType, extra_headers)
    local host = self:getAWSHost()
    local request_method = http_method or "GET"

    local arguments = arguments or {}
    local query_string = self:getRequestArguments(actionName, arguments)
    local request_path = path or "/"

    local uri_args, request_body = arguments, ""
    uri_args.Action = actionName

    local content_type = contentType or "application/x-amz-json-1.1"

    if content_type == "application/x-amz-json-1.1" then
        request_body = cjson.encode(arguments)
    elseif content_type == "application/x-www-form-urlencoded" then
        request_body = query_string
    end

    if request_method ~= "GET" then
        uri_args = {}
    end

    local scheme = "http"
    local port = 80
    if useSSL == true then
        scheme = "https"
        port = 443
    end


    local authorization, awsAuth, authToken = self:getAuthorizationHeader(request_method, request_path, uri_args, request_body)

    local t = self.aws_service_name .. "." .. actionName
    local request_headers = {
        Authorization = authorization,
        ["X-Amz-Date"] = awsAuth.aws_date,
        ["Accept"] = "application/json",
        ["Content-Type"] = content_type,
        ["X-Amz-Target"] = t,
        ["x-amz-security-token"] = authToken
    }
    if ( extra_headers ~= nil ) then
        for headerName, headerValue in pairs(extra_headers) do
            request_headers[headerName] = headerValue
        end
    end


    -- this race condition has to be AFTER the authorization header has been calculated
    if request_method == "GET" then
        request_path = request_path .. "?" .. query_string
    end

    if (self.aws_debug == true) then
        ngx.log(ngx.DEBUG, "Calling AWS:", request_method, " ", scheme, "://", host, ":", port, request_path, ". Body=", request_body)
        local s = tableToString(request_headers)
        ngx.log(ngx.DEBUG, "Calling AWS: Headers:", s)
    end

    local ok, code, headers, status, body = self:getHttpClient():request(self:getRequestObject({
        scheme = scheme,
        ssl_verify = false,
        port = port,
        timeout = timeout or 60000,
        url = request_path, -- "/"
        host = host,
        body = request_body,
        method = request_method,
        headers = request_headers,
        keepalive = self.aws_conn_keepalive or 30000, -- 30s keepalive
        poolsize = self.aws_conn_pool or 100 -- max number of connections allowed in the connection pool
    }))

    if (self.aws_debug == true) then
        local s = tableToString(headers)
        ngx.log(ngx.DEBUG, "AWS Response:", "code=", code, ", headers=", s, ", status=", status, ", body=", body)
    end

    return ok, code, headers, status, body
end

return _M
