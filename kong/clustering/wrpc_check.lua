local http = require "resty.http"

--- detect '/v1/wrpc' endpoint
--- if there is no '/v1/wrpc', fallback to websocket + json
local function check_wrpc_support(conf, cert, cert_key)
  local params = {
    scheme = "https",
    method = "HEAD",

    ssl_verify = true,
    ssl_client_cert = cert,
    ssl_client_priv_key = cert_key,
  }

  if conf.cluster_mtls == "shared" then
    params.ssl_server_name = "kong_clustering"

  else
    -- server_name will be set to the host if it is not explicitly defined here
    if conf.cluster_server_name ~= "" then
      params.ssl_server_name = conf.cluster_server_name
    end
  end

  local c = http.new()
  local res, err = c:request_uri(
    "https://" .. conf.cluster_control_plane .. "/v1/wrpc", params)
  if not res then
    return nil, err
  end

  if res.status == 404 then
    return "v0"
  end

  return "v1"   -- wrpc
end

return check_wrpc_support
