local http  = require "resty.http"
local json  = require "cjson"

local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")

local LOG_PREFIX = "[" .. plugin_name .. "] "
local DEFAULT_METADATA_SERVICE_PORT = 80
local DEFAULT_METADATA_SERVICE_REQUEST_TIMEOUT = 5000
local DEFAULT_METADATA_SERVICE_HOST = "169.254.169.254"

local function fetch_iam_credentials_from_metadata_service(metadata_service_host, metadata_service_port,
                                                           metadata_service_request_timeout)
  metadata_service_host = metadata_service_host or DEFAULT_METADATA_SERVICE_HOST
  metadata_service_port = metadata_service_port or DEFAULT_METADATA_SERVICE_PORT
  metadata_service_request_timeout = metadata_service_request_timeout or DEFAULT_METADATA_SERVICE_REQUEST_TIMEOUT

  local client = http.new()
  client:set_timeout(metadata_service_request_timeout)

  local ok, err = client:connect(metadata_service_host, metadata_service_port)

  if not ok then
    ngx.log(ngx.ERR, LOG_PREFIX, "Could not connect to metadata service: ", err)
    return nil, err
  end

  local role_name_request_res, err = client:request {
    method = "GET",
    path   = "/latest/meta-data/iam/security-credentials/",
  }

  if not role_name_request_res or role_name_request_res == "" then
    ngx.log(ngx.ERR, LOG_PREFIX, "Could not fetch role name from metadata service: ", err)
    return nil, err
  end

  if role_name_request_res.status ~= 200 then
    return nil, LOG_PREFIX, "Fetching role name from metadata service returned status code " ..
                role_name_request_res.status .. " with body " .. role_name_request_res.body
  end

  local iam_role_name = role_name_request_res:read_body()

  ngx.log(ngx.DEBUG, LOG_PREFIX, "Found IAM role on instance with name: ", iam_role_name)

  local ok, err = client:connect(metadata_service_host, metadata_service_port)

  if not ok then
    ngx.log(ngx.ERR, "Could not connect to metadata service: ", err)
    return nil, err
  end

  local iam_security_token_request, err = client:request {
    method = "GET",
    path   = "/latest/meta-data/iam/security-credentials/" .. iam_role_name,
  }

  if not iam_security_token_request then
    return nil, err
  end

  if iam_security_token_request.status == 404 then
    return nil, LOG_PREFIX, "Unable to request IAM credentials for role " .. iam_role_name ..
                " Request returned status code " .. iam_security_token_request.status
  end

  if iam_security_token_request.status ~= 200 then
    return nil, iam_security_token_request:read_body()
  end

  local iam_security_token_data = json.decode(iam_security_token_request:read_body())

  ngx.log(ngx.DEBUG, LOG_PREFIX, "Received temporary IAM credential from metadata service for role '",
                     iam_role_name, "' with session token: ", iam_security_token_data.Token)

  return {
    access_key    = iam_security_token_data.AccessKeyId,
    secret_key    = iam_security_token_data.SecretAccessKey,
    session_token = iam_security_token_data.Token,
  }
end

return fetch_iam_credentials_from_metadata_service
