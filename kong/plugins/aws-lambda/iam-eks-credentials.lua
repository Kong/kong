local kong = kong
local ENV_TOKEN_FILE = os.getenv 'AWS_WEB_IDENTITY_TOKEN_FILE'
local ENV_ROLE_ARN = os.getenv 'AWS_ROLE_ARN'
local DEFAULT_SERVICE_REQUEST_TIMEOUT = 5000


local url = require "socket.url"
local http = require "resty.http"
local json = require "cjson"
local ngx_now = ngx.now
local concat = table.concat
local tostring = tostring

do
  if not (ENV_TOKEN_FILE) then
    -- No variables found, so we're not probably not running on EKS containers
    kong.log.debug("No Web Identity environment variables found for IAM")
  end
end


local function fetchCredentials()
  local client = http.new()
  client:set_timeout(DEFAULT_SERVICE_REQUEST_TIMEOUT)

  local tokenFile, tokenError = io.open(ENV_TOKEN_FILE)

  if not tokenFile then
    return nil, "Failed to open identity token file: " .. tostring(tokenError)
  end

  local response, err = client:request_uri("https://sts.amazonaws.com", {
    method = "POST",
    headers = {
      ["Accept"] = "application/json",
    },
    query = {
      Action = "AssumeRoleWithWebIdentity",
      RoleArn = ENV_ROLE_ARN,
      WebIdentityToken = tokenFile:read("*a"),
      RoleSessionName = "kong",
      Version = "2011-06-15",
    },
  })
  if not response then
    return nil, "Failed to request IAM credentials request returned error: " .. tostring(err)
  end

  if response.status ~= 200 then
    return nil, "Unable to request IAM credentials request returned status code " ..
                response.status .. " " .. tostring(response.body)
  end

  local credentials = json.decode(response.body).AssumeRoleWithWebIdentityResponse.AssumeRoleWithWebIdentityResult.Credentials

  local result = {
    access_key    = credentials.AccessKeyId,
    secret_key    = credentials.SecretAccessKey,
    session_token = credentials.SessionToken,
    expiration    = tonumber(credentials.Expiration)
  }
  return result, nil, result.expiration - ngx_now()
end

local function fetchCredentialsLogged()
  -- wrapper to log any errors
  local creds, err, ttl = fetchCredentials()
  if creds then
    return creds, err, ttl
  end
  kong.log.err(err)
end

return {
  configured = not not ENV_TOKEN_FILE, -- force to boolean
  fetchCredentials = fetchCredentialsLogged,
}
