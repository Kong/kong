-- This code is reverse engineered from the original AWS sdk. Specifically:
-- https://github.com/aws/aws-sdk-js/blob/c175cb2b89576f01c08ebf39b232584e4fa2c0e0/lib/credentials/remote_credentials.js


local function makeset(t)
  for i = 1, #t do
    t[t[i]] = true
  end
  return t
end

local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")

local LOG_PREFIX = "[" .. plugin_name .. " ecs] "
local ENV_RELATIVE_URI = os.getenv 'AWS_CONTAINER_CREDENTIALS_RELATIVE_URI'
local ENV_FULL_URI = os.getenv 'AWS_CONTAINER_CREDENTIALS_FULL_URI'
local FULL_URI_UNRESTRICTED_PROTOCOLS = makeset { "https" }
local FULL_URI_ALLOWED_PROTOCOLS = makeset { "http", "https" }
local FULL_URI_ALLOWED_HOSTNAMES = makeset { "localhost", "127.0.0.1" }
local RELATIVE_URI_HOST = '169.254.170.2'
local DEFAULT_SERVICE_REQUEST_TIMEOUT = 5000

local url = require "socket.url"
local http = require "resty.http"
local json = require "cjson"
local parse_date = require("luatz").parse.rfc_3339
local ngx_now = ngx.now

local ECSFullUri
do
  if not (ENV_RELATIVE_URI or ENV_FULL_URI) then
    -- No variables found, so we're not running on ECS containers
    ngx.log(ngx.NOTICE, LOG_PREFIX, "No ECS environment variables found for IAM")
  else

    -- construct the URL
    local function getECSFullUri()
      if ENV_RELATIVE_URI then
        return 'http://' .. RELATIVE_URI_HOST .. ENV_RELATIVE_URI

      elseif ENV_FULL_URI then
        local parsed_url = url.parse(ENV_FULL_URI)

        if not FULL_URI_ALLOWED_PROTOCOLS[parsed_url.scheme] then
          return nil, 'Unsupported protocol: AWS.RemoteCredentials supports '
                 .. table.concat(FULL_URI_ALLOWED_PROTOCOLS, ',') .. ' only; '
                 .. parsed_url.scheme .. ' requested.'
        end

        if (not FULL_URI_UNRESTRICTED_PROTOCOLS[parsed_url.scheme]) and
           (not FULL_URI_ALLOWED_HOSTNAMES[parsed_url.hostname]) then
             return nil, 'Unsupported hostname: AWS.RemoteCredentials only supports '
                    .. table.concat(FULL_URI_ALLOWED_HOSTNAMES, ',') .. ' for '
                    .. parsed_url.scheme .. '; ' .. parsed_url.scheme .. '://'
                    .. parsed_url.host .. ' requested.'
        end

        return ENV_FULL_URI

      else
        return nil, 'Environment variable AWS_CONTAINER_CREDENTIALS_RELATIVE_URI or '
               .. 'AWS_CONTAINER_CREDENTIALS_FULL_URI must be set to use AWS.RemoteCredentials.'
      end
    end

    local err
    ECSFullUri, err = getECSFullUri()
    if not ECSFullUri then
      ngx.log(ngx.ERR, LOG_PREFIX, "Failed to construct IAM url: ", err)
    else
      -- parse it and set a default port if omitted
      ECSFullUri = url.parse(ECSFullUri)
      ECSFullUri.port = ECSFullUri.port or
                        ({ http = 80, https = 443 })[ECSFullUri.scheme]
    end
  end
end


local function fetchCredentials()

  local client = http.new()
  client:set_timeout(DEFAULT_SERVICE_REQUEST_TIMEOUT)

  local ok, err = client:connect(ECSFullUri.host, ECSFullUri.port)

  if not ok then
    return nil, "Could not connect to metadata service: " .. tostring(err)
  end

  local response, err = client:request {
    method = "GET",
    path   = ECSFullUri.path,
  }

  if not response then
    return nil, "Failed to request IAM credentials request returned error: " .. tostring(err)
  end

  if response.status ~= 200 then
    return nil, "Unable to request IAM credentials request returned status code " ..
                response.status .. " " .. tostring(response:read_body())
  end

  local credentials = json.decode(response:read_body())

  ngx.log(ngx.DEBUG, LOG_PREFIX, "Received temporary IAM credential from ECS metadata " ..
                      "service with session token: ", credentials.Token)

  local result = {
    access_key    = credentials.AccessKeyId,
    secret_key    = credentials.SecretAccessKey,
    session_token = credentials.Token,
    expiration    = parse_date(credentials.Expiration):timestamp()
  }
  return result, nil, result.expiration - ngx_now()
end

local function fetchCredentialsLogged()
  -- wrapper to log any errors
  local creds, err, ttl = fetchCredentials()
  if creds then
    return creds, err, ttl
  end
  ngx.log(ngx.ERR, LOG_PREFIX, err)
end

return {
  configured = not not ECSFullUri, -- force to boolean
  fetchCredentials = fetchCredentialsLogged,
}
