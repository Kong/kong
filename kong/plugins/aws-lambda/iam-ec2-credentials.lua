local http  = require "resty.http"
local json  = require "cjson"
local parse_date = require("luatz").parse.rfc_3339
local ngx_now = ngx.now
local tostring = tostring
local kong = kong


local METADATA_SERVICE_PORT = 80
local METADATA_SERVICE_REQUEST_TIMEOUT = 5000
local METADATA_SERVICE_HOST = "169.254.169.254"
local METADATA_SERVICE_TOKEN_URI = "http://" .. METADATA_SERVICE_HOST .. ":" .. METADATA_SERVICE_PORT ..
                             "/latest/api/token"
local METADATA_SERVICE_IAM_URI = "http://" .. METADATA_SERVICE_HOST .. ":" .. METADATA_SERVICE_PORT ..
                             "/latest/meta-data/iam/security-credentials/"


local function fetch_ec2_credentials(config)
  local client = http.new()
  client:set_timeout(METADATA_SERVICE_REQUEST_TIMEOUT)

  local protocol_version = config.aws_imds_protocol_version
  local imds_session_headers

  if protocol_version == "v1" then
    -- When using IMSDv1, the role is retrieved with a simple GET
    -- request requiring no special headers.
    imds_session_headers = {}

  elseif protocol_version == "v2" then
    -- When using IMSDv2, the role is retrieved with a GET request
    -- that has a valid X-aws-ec2-metadata-token header with a valid
    -- token, which needs to be retrieved with a PUT request.
    local token_request_res, err = client:request_uri(METADATA_SERVICE_TOKEN_URI, {
        method = "PUT",
        headers = {
          ["X-aws-ec2-metadata-token-ttl-seconds"] = "60",
        },
    })

    if not token_request_res then
      return nil, "Could not fetch IMDSv2 token from metadata service: " .. tostring(err)
    end

    if token_request_res.status ~= 200 then
      return nil, "Fetching IMDSv2 token from metadata service returned status code " ..
        token_request_res.status .. " with body " .. token_request_res.body
    end
    imds_session_headers = { ["X-aws-ec2-metadata-token"] = token_request_res.body }

  else
    return nil, "Unrecognized aws_imds_protocol_version " .. tostring(protocol_version) .. " set in configuration"
  end

  local role_name_request_res, err = client:request_uri(METADATA_SERVICE_IAM_URI, {
      headers = imds_session_headers,
  })

  if not role_name_request_res then
    return nil, "Could not fetch role name from metadata service: " .. tostring(err)
  end

  if role_name_request_res.status ~= 200 then
    return nil, "Fetching role name from metadata service returned status code " ..
      role_name_request_res.status .. " with body " .. role_name_request_res.body
  end

  local iam_role_name = role_name_request_res.body
  kong.log.debug("Found IAM role on instance with name: ", iam_role_name)

  local iam_security_token_request, err = client:request_uri(METADATA_SERVICE_IAM_URI .. iam_role_name, {
      headers = imds_session_headers,
  })

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


local function fetchCredentialsLogged(config)
  -- wrapper to log any errors
  local creds, err, ttl = fetch_ec2_credentials(config)
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
