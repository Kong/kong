-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

----
-- This file exists to provide interface methods for Kubernetes operations.
-- It should be moved to its own utils package ASAP.
----


local pl_file = require "pl.file"
local cjson = require("cjson.safe").new()
local http = require "resty.luasocket.http"

local fmt = string.format
local log = ngx.log


local DEBUG = ngx.DEBUG
local ERR = ngx.ERR
local LOG_PREFIX = "[hcv] "


local function get_service_account_token(token_file)
  -- return the kubernetes service account jwt or err
  return pl_file.read(token_file or "/run/secrets/kubernetes.io/serviceaccount/token")
end


local function cache_key(config)
  return fmt("vaults:credentials:%s:%s:%s:%s:%s",
             config.vault_host,
             config.vault_port,
             config.auth_method,
             config.kube_role,
             config.kube_auth_path)
end


local function kube_vault_token_exchange(config)
  log(DEBUG, "no vault token in cache - getting one")

  local kube_role = config.kube_role or "default"
  log(DEBUG, LOG_PREFIX, "using kubernetes service account vault authentication mechanism for role: ", kube_role)

  -- get the current kube service account context JWT
  local kube_jwt, err = get_service_account_token(config.kube_api_token_file)
  if err then
    log(ERR, LOG_PREFIX, "error loading kubernetes service account jwt from filesystem: ", err)
    return
  end

  -- exchange the jwt for a vault token
  local c = http.new()

  local kube_auth_path = (config.kube_auth_path or "kubernetes"):gsub("^/", ""):gsub("/$", "")

  local req_path = config.vault_host .. "/v1/auth/" .. kube_auth_path .. "/login"
  local req_data = {
    jwt = kube_jwt,
    role = kube_role,
  }

  local res, err = c:request_uri(req_path, {
    -- add a namespace to authenticate to, else use root.
    headers = {
      ["X-Vault-Namespace"] = config.auth_namespace or "root",
    },
    method = "POST",
    body = cjson.encode(req_data),
  })

  if err then
    log(ERR, LOG_PREFIX, "failure when exchanging kube service account jwt for vault token: ", err)
    return
  end

  if res.status ~= 200 then
    log(ERR, LOG_PREFIX, "invalid response code ", res.status, " received when exchanging kube service account jwt for vault token: ", res.body)
    return
  end

  -- capture the current token and ttl
  local vault_response = cjson.decode(res.body)
  return vault_response.auth.client_token, nil, vault_response.auth.lease_duration
end



return {
  cache_key = cache_key,
  get_service_account_token = get_service_account_token,
  vault_token_exchange = kube_vault_token_exchange,
}
