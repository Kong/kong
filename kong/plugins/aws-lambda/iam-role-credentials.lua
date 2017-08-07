local http  = require 'resty.http'
local json  = require 'cjson'
local cache = require 'kong.tools.database_cache'

local CACHE_IAM_INSTANCE_CREDS_DURATION = 60 -- seconds to cache credentials from metadata service
local IAM_CREDENTIALS_CACHE_KEY = "plugin.aws-lambda.iam_role_temp_creds"

local function fetch_iam_credentials_from_metadata_service(metadata_service_host, metadata_service_port)
    local client = http.new()
    local ok, err = client:connect(metadata_service_host, metadata_service_port) 
    
    if not ok then
      ngx.log(ngx.ERR, "[aws-lambda] Could not connect to metadata service: ", err)
      return nil, err
    end
    
    local role_name_request_res, err = client:request {
      method = "GET",
      path = "/latest/meta-data/iam/security-credentials/"
    }
     
    if not role_name_request_res or role_name_request_res == "" then
          ngx.log(ngx.ERR, "[aws-lambda] Could not fetch role name from metadata service: ", err)
        return nil, err
    end 
     
    if role_name_request_res.status ~= 200 then
      return nil, "[aws-lambda] Fetching role name from metadata service returned status code "..
                  role_name_request_res.status  .. "with body " .. role_name_request_res.body
    end
           
    local iam_role_name = role_name_request_res:read_body() 
    
    ngx.log(ngx.DEBUG, "[aws-lambda] IAM role '" .. iam_role_name ..
                       "' is available through metadata service, fetching IAM credentials")
    
    local ok, err = client:connect(metadata_service_host, metadata_service_port) 
    
    if not ok then
      ngx.log(ngx.ERR, "Could not connect to metadata service: ", err)
      return nil, err
    end
    
    local iam_security_token_request, err = client:request {
      method = "GET",
      path = "/latest/meta-data/iam/security-credentials/" .. iam_role_name
    }    
    
    if not iam_security_token_request then
        return nil, err
    end
    
    if iam_security_token_request.status == 404 then
        return nil, '[aws-lambda] Unable to request IAM credentials for role' .. iam_role_name ..
                    ' Request returned status code ' .. iam_security_token_request.status
    end

    if iam_security_token_request.status ~= 200 then
        return nil, iam_security_token_request:read_body()
    end

    local iam_security_token_data = json.decode(iam_security_token_request:read_body())

    ngx.log(ngx.DEBUG, "[aws-lambda] Received temporary IAM credential from metadata service for role '" ..
                       iam_role_name .. "' with session token " .. iam_security_token_data.Token)

    return {
        access_key = iam_security_token_data.AccessKeyId,
        secret_key = iam_security_token_data.SecretAccessKey,
        session_token = iam_security_token_data.Token
    }
end

local function get_iam_credentials_from_instance_profile(metadata_service_host, metadata_service_port)
    metadata_service_host = metadata_service_host or '169.254.169.254'
    metadata_service_port = metadata_service_port or 80

    local iam_profile_credentials, err = cache.get_or_set(IAM_CREDENTIALS_CACHE_KEY, CACHE_IAM_INSTANCE_CREDS_DURATION,
                                       fetch_iam_credentials_from_metadata_service, metadata_service_host, metadata_service_port)
    if not iam_profile_credentials then
      ngx.log(ngx.ERR, err)
      return ngx.exit(ngx.ERROR)
    end

  return iam_profile_credentials
end

return get_iam_credentials_from_instance_profile