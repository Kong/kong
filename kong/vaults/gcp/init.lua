-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local meta = require "kong.meta"
local gcp = require "resty.gcp"
local access_token = require "resty.gcp.request.credentials.accesstoken"
local cjson = require("cjson.safe")


local decode_base64 = ngx.decode_base64
local fmt = string.format
local type = type
local getenv = os.getenv


local GCP
local GCP_PROJECT_ID
local GCP_ACCESS_TOKEN


local function init()
  GCP_PROJECT_ID = getenv("GCP_PROJECT_ID")

  -- GCP_SERVICE_ACCOUNT or Workload Identity will be read to get the Access Token
  GCP = gcp()

  -- only try to initialize access token if env var is set otherwise
  -- it may print to error log
  if getenv("GCP_SERVICE_ACCOUNT") then
    local ok, token = pcall(access_token.new)
    -- ignore error as user may not using GCP vault and not configured it
    if ok and token then
      GCP_ACCESS_TOKEN = token
    end
  end
end


local function get(conf, resource, version)
  local project_id = conf.project_id or GCP_PROJECT_ID

  if not project_id then
    return nil, "gcp secret manager requires project_id"
  end

  if not version then
    -- If version is missing fetching the "latest" version
    version = "latest"
  end

  if not GCP_ACCESS_TOKEN then
    local ok, token = pcall(access_token.new)
    if not ok or not token then
      ngx.log(ngx.ERR, "error while creating token (invalid service account): ", token)
      return nil, "GCP_SERVICE_ACCOUNT invalid (invalid service account)"
    end

    GCP_ACCESS_TOKEN = token

  elseif GCP_ACCESS_TOKEN:needsRefresh() then

    local pok, ok = pcall(GCP_ACCESS_TOKEN.refresh, GCP_ACCESS_TOKEN)
    if not pok or not ok then
      ngx.log(ngx.ERR, "error while refreshing token: ", ok)
      return nil, "GCP_SERVICE_ACCOUNT invalid (invalid service account)"
    end
  end

  local params = { projectsId = project_id, secretsId = resource, versionsId = version}

  local ok, res, err = pcall(GCP.secretmanager_v1.versions.access, GCP_ACCESS_TOKEN, params)
  if not ok then
    return nil, res
  end

  if not res then
    local payload = cjson.decode(err)
    if type(payload) == 'table' then
      return nil, fmt("unable to retrieve secret from gcp secret manager (code : %s, status: %s)", payload.error.code, payload.error.status)
    else
      return nil, fmt("unable to retrieve secret from gcp secret manager: %s", err)
    end
  end

  if type(res) ~= "table" then
    ngx.log(ngx.ERR, "error while retrieving secret from gcp secret manager: ", res)
    return nil, "unable to retrieve secret from gcp secret manager (invalid response)"
  end

  local payload = res.payload
  if type(payload) ~= "table" then
    return nil, "unable to retrieve secret from gcp secret manager (invalid response)"
  end

  local secret_encoded = payload.data
  if type(secret_encoded) ~= "string" then
    return nil, "unable to retrieve secret from gcp secret manager (invalid secret string)"
  end

  local secret = decode_base64(secret_encoded)

  return secret
end


return {
  name = "gcp",
  VERSION = meta.core_version,
  init = init,
  get = get,
  license_required = true,
}
