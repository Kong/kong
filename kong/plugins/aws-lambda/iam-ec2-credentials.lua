local http  = require "resty.http"
local json  = require "cjson"
local parse_date = require("luatz").parse.rfc_3339
local ngx_now = ngx.now
local tostring = tostring
local kong = kong


local METADATA_SERVICE_PORT = 80
local METADATA_SERVICE_REQUEST_TIMEOUT = 5000
local METADATA_SERVICE_HOST = "169.254.169.254"
local METADATA_SERVICE_URI = "http://" .. METADATA_SERVICE_HOST .. ":" .. METADATA_SERVICE_PORT ..
                             "/latest/meta-data/iam/security-credentials/"


local function fetch_ec2_credentials()
  local client = http.new()
  client:set_timeout(METADATA_SERVICE_REQUEST_TIMEOUT)
  local role_name_request_res, err = client:request_uri(METADATA_SERVICE_URI)

  if not role_name_request_res then
    return nil, "Could not fetch role name from metadata service: " .. tostring(err)
  end

  if role_name_request_res.status ~= 200 then
    return nil, "Fetching role name from metadata service returned status code " ..
                role_name_request_res.status .. " with body " .. role_name_request_res.body
  end

  local iam_role_name = role_name_request_res.body

  kong.log.debug("Found IAM role on instance with name: ", iam_role_name)

  local iam_security_token_request, err = client:request_uri(METADATA_SERVICE_URI .. iam_role_name)
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
                " " .. tostring(iam_security_token_request.body)
  end

  local iam_security_token_data = json.decode(iam_security_token_request.body)

  kong.log.debug("Received temporary IAM credential from metadata service for role '",
                 iam_role_name, "' with session token: ", iam_security_token_data.Token)

  local result = {
    access_key    = iam_security_token_data.AccessKeyId,
    secret_key    = iam_security_token_data.SecretAccessKey,
    session_token = iam_security_token_data.Token,
    expiration    = parse_date(iam_security_token_data.Expiration):timestamp()
  }
  return result, nil, result.expiration - ngx_now()
end


local function fetchCredentialsLogged()
  -- wrapper to log any errors
  local creds, err, ttl = fetch_ec2_credentials()
  if creds then
    return creds, err, ttl
  end
  kong.log.err(err)
end


return {
  -- we set configured to true, because we cannot properly test it. Only by
  -- using the metadata url, but on a non-EC2 machine that will block on
  -- timeouts and hence prevent Kong from starting quickly. So for now
  -- we're just using the EC2 fetcher as the final fallback.
  configured = true,
  fetchCredentials = fetchCredentialsLogged,
}
