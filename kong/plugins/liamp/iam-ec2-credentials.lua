local http  = require "resty.http"
local json  = require "cjson"
local parse_date = require("luatz").parse.rfc_3339


local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")


local LOG_PREFIX = "[" .. plugin_name .. " ec2] "
local METADATA_SERVICE_PORT = 80
local METADATA_SERVICE_REQUEST_TIMEOUT = 5000
local METADATA_SERVICE_HOST = "169.254.169.254"


local function fetch_ec2_credentials()

  local client = http.new()
  client:set_timeout(METADATA_SERVICE_REQUEST_TIMEOUT)

  local ok, err = client:connect(METADATA_SERVICE_HOST, METADATA_SERVICE_PORT)

  if not ok then
    return nil, "Could not connect to metadata service: " .. tostring(err)
  end

  local role_name_request_res, err = client:request {
    method = "GET",
    path   = "/latest/meta-data/iam/security-credentials/",
  }

  if not role_name_request_res then
    return nil, "Could not fetch role name from metadata service: " .. tostring(err)
  end

  if role_name_request_res.status ~= 200 then
    return nil, "Fetching role name from metadata service returned status code " ..
                role_name_request_res.status .. " with body " .. role_name_request_res.body
  end

  local iam_role_name = role_name_request_res:read_body()

  ngx.log(ngx.DEBUG, LOG_PREFIX, "Found IAM role on instance with name: ", iam_role_name)

  local ok, err = client:connect(METADATA_SERVICE_HOST, METADATA_SERVICE_PORT)

  if not ok then
    return nil, "Could not connect to metadata service: " .. tostring(err)
  end

  local iam_security_token_request, err = client:request {
    method = "GET",
    path   = "/latest/meta-data/iam/security-credentials/" .. iam_role_name,
  }

  if not iam_security_token_request then
    return nil, "Failed to request IAM credentials for role " .. iam_role_name ..
                " Request returned error: " .. tostring(err)
  end

  if iam_security_token_request.status == 404 then
    return nil, "Unable to request IAM credentials for role " .. iam_role_name ..
                " Request returned status code 404."
  end

  if iam_security_token_request.status ~= 200 then
    return nil, "Unable to request IAM credentials for role" .. iam_role_name ..
                " Request returned status code " .. iam_security_token_request.status ..
                " " .. tostring(iam_security_token_request:read_body())
  end

  local iam_security_token_data = json.decode(iam_security_token_request:read_body())

  ngx.log(ngx.DEBUG, LOG_PREFIX, "Received temporary IAM credential from metadata service for role '",
                     iam_role_name, "' with session token: ", iam_security_token_data.Token)

  return {
    access_key    = iam_security_token_data.AccessKeyId,
    secret_key    = iam_security_token_data.SecretAccessKey,
    session_token = iam_security_token_data.Token,
    expiration    = parse_date(iam_security_token_data.Expiration):timestamp()
  }
end

local function fetchCredentialsLogged()
  -- wrapper to log any errors
  local creds, err = fetch_ec2_credentials()
  if creds then
    return creds
  end
  ngx.log(ngx.ERR, LOG_PREFIX, err)
end

return {
  -- we set configured to true, because we cannot properly test it. Only by
  -- using the metadata url, but on a non-EC2 machine that will block on
  -- timeouts and hence prevent Kong from starting quickly. So for now
  -- we're just using the EC2 fetcher as the final fallback.
  configured = true,
  fetchCredentials = fetchCredentialsLogged,
}

