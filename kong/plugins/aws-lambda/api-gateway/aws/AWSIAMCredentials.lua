--
-- Created by IntelliJ IDEA.
-- User: nramaswa
-- Date: 6/4/14
-- Time: 5:03 PM
-- To change this template use File | Settings | File Templates.
--

local cjson = require "cjson"
local http = require "kong.plugins.aws-lambda.api-gateway.aws.httpclient.http"
local url = require "kong.plugins.aws-lambda.api-gateway.aws.httpclient.url"
local awsDate = require "kong.plugins.aws-lambda.api-gateway.aws.AwsDateConverter"
local cacheCls = require "kong.plugins.aws-lambda.api-gateway.cache.cache"

local DEFAULT_SECURITY_CREDENTIALS_HOST = "169.254.169.254"
local DEFAULT_SECURITY_CREDENTIALS_PORT = "80"
local DEFAULT_SECURITY_CREDENTIALS_URL = "/latest/meta-data/iam/security-credentials/"
-- use GET /latest/meta-data/iam/security-credentials/ to auto-discover the IAM Role
local DEFAULT_TOKEN_EXPIRATION = 60*60*24 -- in seconds

-- configure cache Manager for IAM crendentials
local iamCache = cacheCls:new()

-- per nginx process cache to store IAM credentials
local cache = {
    IamUser = nil,
    AccessKeyId = nil,
    SecretAccessKey = nil,
    Token = nil,
    ExpireAt = nil,
    ExpireAtTimestamp = nil
}

local function tableToString(table_ref)
    local s = ""
    local o = table_ref or {}
    for k,v in pairs(o) do
        s = s .. ", " .. k .. "=" .. tostring(v)
    end
    return s
end

local function initIamCache(shared_cache_dict)
    local localCache = require "kong.plugins.aws-lambda.api-gateway.cache.store.localCache":new({
        dict = shared_cache_dict,
        ttl = function (value)
            local value_o = cjson.decode(value)
            local expiryTimeUTC = value.ExpireAtTimestamp or awsDate.convertDateStringToTimestamp(value_o.ExpireAt, true)
            local expiryTimeInSeconds = expiryTimeUTC - os.time()
            return math.min(DEFAULT_TOKEN_EXPIRATION, expiryTimeInSeconds)
        end
    })

    iamCache:addStore(localCache)
end

local AWSIAMCredentials = {}

---
-- @param o Configuration object
-- o.iam_user                       -- optional. iam_user. if not defined it'll be auto-discovered
-- o.security_credentials_timeout   -- optional. specifies when the token should expire. Defaults to 24 hours
-- o.security_credentials_host      -- optional. AWS Host to read credentials from. Defaults to "169.254.169.254"
-- o.security_credentials_port      -- optional. AWS Port to read credentials. Defaults to 80.
-- o.security_credentials_url       -- optional. AWS URI to read credentials. Defaults to "/latest/meta-data/iam/security-credentials/"
-- o.shared_cache_dict              -- optional. For performance improvements the credentials may be stored in a share dict.
--
function AWSIAMCredentials:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if (o ~= nil) then
        self.iam_user = o.iam_user
        self.security_credentials_timeout = o.security_credentials_timeout or DEFAULT_TOKEN_EXPIRATION
        self.security_credentials_host = o.security_credentials_host or DEFAULT_SECURITY_CREDENTIALS_HOST
        self.security_credentials_port = o.security_credentials_port or DEFAULT_SECURITY_CREDENTIALS_PORT
        self.security_credentials_url = o.security_credentials_url or DEFAULT_SECURITY_CREDENTIALS_URL
        self.shared_cache_dict = o.shared_cache_dict
        if (o.shared_cache_dict ~= nil) then
            initIamCache(o.shared_cache_dict)
        end
        local s = tableToString(o)
        ngx.log(ngx.DEBUG, "Initializing AWSIAMCredentials with object:", s)
    end
    return o
end

function AWSIAMCredentials:loadCredentialsFromSharedDict()
    local iamCreds = iamCache:get("iam_credentials")
    if (iamCreds ~= nil) then
        iamCreds = cjson.decode(iamCreds)
        cache.AccessKeyId = iamCreds.AccessKeyId
        cache.SecretAccessKey = iamCreds.SecretAccessKey
        cache.Token = iamCreds.Token
        cache.ExpireAt = iamCreds.ExpireAt
        cache.ExpireAtTimestamp = iamCreds.ExpireAtTimestamp
        ngx.log(ngx.DEBUG, "Cache has been loaded from Shared Cache" )
    end
end

---
-- Auto discover the IAM User
function AWSIAMCredentials:fetchIamUser()
    ngx.log(ngx.DEBUG, "Fetching IAM User from:",
        self.security_credentials_host, ":", self.security_credentials_port, self.security_credentials_url)
    local hc1 = http:new()

    local ok, code, headers, status, body = hc1:request{
        host = self.security_credentials_host,
        port = self.security_credentials_port,
        url = self.security_credentials_url,
        method = "GET",
        keepalive = 30000, -- 30s keepalive
        poolsize = 50
    }

    if (code == ngx.HTTP_OK and body ~= nil) then
        cache.IamUser = body
        ngx.log(ngx.DEBUG, "found user:" .. tostring(body))
        return cache.IamUser
    end
    ngx.log(ngx.WARN, "Could not fetch iam user from:", self.security_credentials_host, ":", self.security_credentials_port, self.security_credentials_url)
    return nil
end

function AWSIAMCredentials:getIamUser()
    local cachedIamUser = self.iam_user or cache.IamUser
    if (cachedIamUser ~= nil) then
        return cachedIamUser, true
    end
    ngx.log(ngx.WARN, "No iam_user provided. To improve performance please define one to avoid extra round trips to AWS")
    return self:fetchIamUser(), false
end

---
-- Get credentials for the IAM User
function AWSIAMCredentials:fetchSecurityCredentialsFromAWS()
    local iamURL = self.security_credentials_url .. self:getIamUser() .. "?DurationSeconds=" .. self.security_credentials_timeout

    local hc1 = http:new()

    local ok, code, headers, status, body = hc1:request{
        host = self.security_credentials_host,
        port = self.security_credentials_port,
        url = iamURL,
        method = "GET",
        keepalive = 30000, -- 30s keepalive
        poolsize = 50
    }

    ngx.log(ngx.DEBUG, "AWS Response:" .. tostring(body))

    local aws_response = cjson.decode(body)

    if (aws_response["Code"] == "Success") then
        -- set the values and the expiry time
        cache.AccessKeyId = aws_response["AccessKeyId"]
        cache.SecretAccessKey = aws_response["SecretAccessKey"]
        --local token = url:encodeUrl(aws_response["Token"])
        cache.Token = aws_response["Token"]
        cache.ExpireAt = aws_response["Expiration"]
        cache.ExpireAtTimestamp = awsDate.convertDateStringToTimestamp(cache.ExpireAt, true)
        if (cache.ExpireAtTimestamp - os.time() > 0) then
            iamCache:put("iam_credentials", cjson.encode(cache))
        end
        return true
    end

    ngx.log(ngx.WARN, "Could not read credentials from:", self.security_credentials_host, ":", self.security_credentials_port, iamURL)
    return false
end

function AWSIAMCredentials:getSecurityCredentials()
    self:loadCredentialsFromSharedDict()
    if (cache.Token == nil or cache.SecretAccessKey == nil or cache.AccessKeyId == nil) then
        ngx.log(ngx.DEBUG, "Obtaining a new token as the cache is empty.")
        self:fetchSecurityCredentialsFromAWS()
    end

    -- http://wiki.nginx.org/HttpLuaModule#ngx.time
    local now_in_secs = ngx.time()
    local expireAtTimestamp = cache.ExpireAtTimestamp or now_in_secs

    if (now_in_secs >= expireAtTimestamp) then
        ngx.log(ngx.WARN, "Current token expired " .. tostring(expireAtTimestamp - now_in_secs) .. " seconds ago. Obtaining a new token.")
        self:fetchSecurityCredentialsFromAWS()
    end

    return cache.AccessKeyId, cache.SecretAccessKey, cache.Token, cache.ExpireAt, cache.ExpireAtTimestamp
end

return AWSIAMCredentials
